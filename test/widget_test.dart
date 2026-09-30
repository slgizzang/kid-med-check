import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kid_med_check/logic/age_rule.dart';
import 'package:kid_med_check/logic/drug_name_extractor.dart';
import 'package:kid_med_check/logic/dur_api.dart';
import 'package:kid_med_check/logic/label_age.dart';
import 'package:kid_med_check/logic/similarity.dart';
import 'package:kid_med_check/ui/theme.dart';
import 'package:kid_med_check/logic/models.dart';

void main() {
  group('AgeRule', () {
    test('12세 미만 금기: 5세는 해당, 13세는 해당 안 됨', () {
      final r = AgeRule.parse('만 12세 미만의 소아');
      expect(r.appliesTo(5 * 12), isTrue);
      expect(r.appliesTo(13 * 12), isFalse);
      expect(r.appliesTo(12 * 12), isFalse);
    });

    test('개월 단위', () {
      final r = AgeRule.parse('6개월 미만 영아');
      expect(r.appliesTo(3), isTrue);
      expect(r.appliesTo(7), isFalse);
    });

    test('2세 이하는 만 2세 11개월까지 포함', () {
      final r = AgeRule.parse('2세 이하');
      expect(r.appliesTo(35), isTrue);
      expect(r.appliesTo(36), isFalse);
    });

    test('구간(6개월 이상 2세 미만)', () {
      final r = AgeRule.parse('6개월 이상 2세 미만');
      expect(r.appliesTo(12), isTrue);
      expect(r.appliesTo(3), isFalse);
      expect(r.appliesTo(60), isFalse);
    });

    test('떨어진 범위는 OR', () {
      final r = AgeRule.parse('12세 미만 소아 및 65세 이상 고령자');
      expect(r.appliesTo(60), isTrue);
      expect(r.appliesTo(30 * 12), isFalse);
      expect(r.appliesTo(70 * 12), isTrue);
    });

    test('숫자가 없으면 판단 불가', () {
      expect(AgeRule.parse('고령자').appliesTo(60), isNull);
      final child = AgeRule.parse('- 안전성 및 유효성 미확립- 페노치아진계 약물을 소아에 투여한 경우 추체외로증상');
      expect(child.appliesTo(21), isTrue);
      expect(child.appliesTo(13 * 12), isFalse);
      expect(child.conditions.single.assumed, isTrue);
      expect(AgeRule.parse('신생아').appliesTo(0), isTrue);
    });
  });

  group('DrugNameExtractor', () {
    test('처방전 텍스트에서 약 이름 추출', () {
      const text = '처방 의약품의 명칭\n'
          '1 타이레놀정500밀리그램(아세트아미노펜) 1 3 3\n'
          '코푸시럽 5ml 3회\n'
          '본인부담금액 3,000원\n'
          '뮤테란캡슐100밀리그램';
      final names = DrugNameExtractor.extract(text);
      expect(names, contains('타이레놀정'));
      expect(names, contains('코푸시럽'));
      expect(names, contains('뮤테란캡슐'));
      expect(names.any((n) => n.contains('부담')), isFalse);
    });

    test('띄어쓰기·줄바꿈으로 끊긴 이름을 붙이고, 제형만 있는 건 버린다', () {
      expect(DrugNameExtractor.extract('맥시부펜 현탁액 5mL 3회'), ['맥시부펜현탁액']);
      expect(DrugNameExtractor.extract('세토펜\n현탁액 4ml\n1일 3회 식후 30분'),
          ['세토펜현탁액']);
      expect(DrugNameExtractor.extract('오구멘틴듀오 건조시럽 6ml'), ['오구멘틴듀오건조시럽']);
      expect(DrugNameExtractor.extract('홍길동 님\n코대원 포르테 시럽 5ml'),
          ['코대원포르테시럽']);
      expect(DrugNameExtractor.extract('타이레놀정 코푸시럽'), ['타이레놀정', '코푸시럽']);
      expect(DrugNameExtractor.extract('현탁액\n건조시럽 5ml'), isEmpty);
      expect(DrugNameExtractor.extract('잘 흔들어 현탁액을 복용'), isEmpty);
    });

    test('검색 대체어', () {
      expect(DrugNameExtractor.searchVariants('코대원포르테시럽'), ['코대원포르테시럽', '코대원포르테']);
      expect(DrugNameExtractor.searchVariants('세토펜현탁액'), ['세토펜현탁액', '세토펜']);
      expect(DrugNameExtractor.searchVariants('코대원'), ['코대원']);
      // "포타"처럼 두 글자로 줄이면 "로포타현탁액" 같은 엉뚱한 약이 걸리므로 줄이지 않는다
      expect(DrugNameExtractor.searchVariants('포타겔'), ['포타겔']);
    });

    test('검색용 이름 정리', () {
      expect(DrugNameExtractor.toSearchName('타이레놀정500밀리그램(아세트아미노펜)'),
          '타이레놀정');
      expect(DrugNameExtractor.toSearchName('타이레놀8시간이알서방정'), '타이레놀8시간이알서방정');
      expect(DrugNameExtractor.splitManual('코푸시럽, 슈다페드정\n뮤테란'),
          ['코푸시럽', '슈다페드정', '뮤테란']);
    });
  });

  group('DurApi', () {
    test('JSON 응답 파싱 (response 래퍼 없음, item 리스트)', () async {
      final client = MockClient((req) async {
        expect(req.url.queryParameters['itemName'], '샘플정');
        expect(req.url.queryParameters['serviceKey'], 'a+b/c==');
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'header': {'resultCode': '00', 'resultMsg': 'NORMAL SERVICE.'},
            'body': {
              'items': [
                {
                  'ITEM_NAME': '샘플정',
                  'ENTP_NAME': '샘플제약',
                  'INGR_KOR_NAME': '샘플성분',
                  'PROHBT_CONTENT': '만 12세 미만의 소아',
                },
              ],
              'totalCount': 1,
            },
          })),
          200,
        );
      });
      // Encoding 키(%2B 등)를 넣어도 디코딩되는지
      final rows = await DurApi('a%2Bb%2Fc%3D%3D', client: client)
          .searchAgeTaboo('샘플정');
      expect(rows, hasLength(1));
      expect(rows.first.itemName, '샘플정');
      expect(rows.first.rule.appliesTo(60), isTrue);

      final check = DrugCheck('샘플정')..rows = rows;
      check.evaluate(60);
      expect(check.status, CheckStatus.danger);
    });

    test('response 래퍼 + items.item 단일 객체', () async {
      final client = MockClient((_) async => http.Response.bytes(
            utf8.encode(jsonEncode({
              'response': {
                'header': {'resultCode': '00'},
                'body': {
                  'items': {
                    'item': {'ITEM_NAME': 'A정', 'PROHBT_CONTENT': '2세 미만'}
                  }
                }
              }
            })),
            200,
          ));
      final rows = await DurApi('k', client: client).searchAgeTaboo('A정');
      expect(rows.single.rule.appliesTo(60), isFalse);
    });

    test('약 설명: e약은요 우선, 실패하면 DUR 품목 분류', () async {
      final client = MockClient((req) async {
        if (req.url.path.contains('DrbEasyDrugInfoService')) {
          if (req.url.queryParameters['itemName'] == '없는약') {
            return http.Response('<OpenAPI_ServiceResponse><cmmMsgHeader><returnAuthMsg>'
                'SERVICE_KEY_IS_NOT_REGISTERED_ERROR</returnAuthMsg></cmmMsgHeader></OpenAPI_ServiceResponse>', 200);
          }
          return http.Response.bytes(
              utf8.encode(jsonEncode({
                'header': {'resultCode': '00'},
                'body': {
                  'items': [
                    {'itemName': '타이레놀정500밀리그람', 'efcyQesitm': '<p>이 약은 해열 및 진통에 사용합니다.</p>'}
                  ]
                }
              })),
              200);
        }
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'header': {'resultCode': '00'},
              'body': {
                'items': [
                  {'ITEM_NAME': '없는약정', 'CLASS_NAME': '해열.진통.소염제', 'ETC_OTC_NAME': '일반의약품'}
                ]
              }
            })),
            200);
      });
      final api = DurApi('k', client: client);
      final a = await api.searchDrugInfo('타이레놀');
      expect(a!.efficacy, '이 약은 해열 및 진통에 사용합니다.');
      final b = await api.searchDrugInfo('없는약');
      expect(b!.className, '해열.진통.소염제');
      expect(b.source, 'DUR 품목정보');
    });

    test('XML 인증 오류는 친절한 메시지로', () async {
      final client = MockClient((_) async => http.Response(
          '<OpenAPI_ServiceResponse><cmmMsgHeader><returnAuthMsg>'
          'SERVICE_KEY_IS_NOT_REGISTERED_ERROR</returnAuthMsg><returnReasonCode>30'
          '</returnReasonCode></cmmMsgHeader></OpenAPI_ServiceResponse>',
          200));
      expect(
        () => DurApi('k', client: client).searchAgeTaboo('A'),
        throwsA(isA<DurApiException>().having(
            (e) => e.message, 'message', contains('인증키'))),
      );
    });
  });

  group('LabelAge (설명서 사용 연령)', () {
    const potagel = '이 약은 성인의 식도, 위·십이지장과 관련된 통증의 완화, 성인의 급·만성 설사, '
        '24개월 이상 소아의 급성 설사에 사용합니다.';
    const lamno = '성인은 1일 2포(2 g)~8포(8 g), 2세 이상의 소아는 1일 1포(1 g)~4포(4 g)를 복용합니다.';

    test('21개월 아이: 포타겔(24개월 이상), 람노스산(2세 이상) 모두 해당', () {
      final a = LabelAge.check(potagel, 21)!;
      expect(a.months, 24);
      expect(a.evidence, '24개월 이상 소아');
      expect(a.prohibited, isFalse);
      expect(LabelAge.check(lamno, 21)!.evidence, '2세 이상의 소아');
      expect(LabelAge.check(potagel, 30), isNull);
    });

    test('금지 문구와 성인용 문구', () {
      final p = LabelAge.check('6개월 미만의 영아는 복용하지 마십시오.', 5)!;
      expect(p.prohibited, isTrue);
      expect(LabelAge.check('만 12세 이상 소아 및 성인: 1회 1~2정', 60)!.months, 144);
      expect(LabelAge.check('65세 이상 고령자는 신중히 복용하십시오. 1일 3회 5~10 mL', 21),
          isNull);
    });

    test('DUR 목록에 없어도 설명서 연령 미만이면 주황 상태', () {
      final c = DrugCheck('포타겔현탁액')..rows = const [];
      c.evaluate(21);
      expect(c.status, CheckStatus.notListed);
      c.info = DrugInfo(itemName: '포타겔현탁액', efficacy: potagel, source: 'e약은요');
      c.applyLabel(21);
      expect(c.status, CheckStatus.labelCaution);
    });
  });

  test('성분정보 연령 기준으로 나이 없는 금기를 보완', () {
    final row = TabooRow.fromJson({
      'ITEM_NAME': '명인클로르프로마진염산염정50mg',
      'INGR_CODE': 'D000123',
      'PROHBT_CONTENT': '추체외로증상 특히 운동장애가 나타나기 쉬움',
    });
    expect(row.rule.appliesTo(21), isNull);
    row.applyAgeBase('12세 미만');
    expect(row.rule.appliesTo(21), isTrue);
    expect(row.ageBase, '12세 미만');
  });

  group('비슷한 약 찾기', () {
    List<String> rank(String q, List<String> names) =>
        ([...names]..sort((a, b) => nameScore(q, a).compareTo(nameScore(q, b))));

    test('오타("포타갤")도 포타겔현탁액이 1순위, 중간에만 겹치는 로포타는 뒤로', () {
      expect(rank('포타갤', ['로포타현탁액', '포타디정', '포타겔현탁액']).first, '포타겔현탁액');
      expect(rank('포타겔', ['로포타현탁액', '포타겔현탁액']).first, '포타겔현탁액');
    });

    test('앞부분만 입력해도 맞는 제품', () {
      expect(rank('코대원포르테', ['코대원정', '코대원에스시럽', '코대원포르테시럽']).first, '코대원포르테시럽');
      expect(rank('타이레놀', ['어린이타이레놀산', '타세놀정', '타이레놀정']).first, '타이레놀정');
    });

    test('제품명 정리', () {
      final h = ProductHit(fullName: '포타겔현탁액(디옥타헤드랄스멕타이트)');
      expect(h.displayName, '포타겔현탁액');
      expect(ProductHit(fullName: '타이레놀정500밀리그램(아세트아미노펜)').searchName, '타이레놀정');
    });

    test('API로 가장 비슷한 제품과 후보 고르기', () async {
      final client = MockClient((req) async {
        final q = req.url.queryParameters['itemName'];
        final isDur = req.url.path.contains('getDurPrdlstInfoList03');
        List<Map<String, String>> items = [];
        if (isDur && q == '포타') {
          items = [
            {'ITEM_NAME': '로포타현탁액(폴리스티렌설폰산칼슘)', 'ENTP_NAME': '대원제약'},
            {'ITEM_NAME': '포타겔현탁액(디옥타헤드랄스멕타이트)', 'ENTP_NAME': '대웅제약', 'MATERIAL_NAME': '디옥타헤드랄스멕타이트,,3,그램,'},
          ];
        }
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'header': {'resultCode': '00'},
              'body': {'items': items}
            })),
            200);
      });
      final res = await DurApi('k', client: client).resolve('포타갤');
      expect(res.best!.displayName, '포타겔현탁액');
      expect(res.best!.ingredient, '디옥타헤드랄스멕타이트');
      expect(res.ambiguous, isFalse);
    });

    test('여러 약이 맞으면(코대원) 하나로 정하지 않고 고르게 한다', () async {
      final client = MockClient((req) async {
        final isDur = req.url.path.contains('getDurPrdlstInfoList03');
        final q = req.url.queryParameters['itemName'] ?? '';
        final items = isDur
            ? ['코대원정', '코대원포르테시럽', '코대원에스시럽']
                .where((n) => n.contains(q))
                .map((n) => {'ITEM_NAME': n})
                .toList()
            : <Map<String, String>>[];
        return http.Response.bytes(
            utf8.encode(jsonEncode({'header': {'resultCode': '00'}, 'body': {'items': items}})),
            200);
      });
      final api = DurApi('k', client: client);
      final res = await api.resolve('코대원');
      expect(res.best, isNull);
      expect(res.ambiguous, isTrue);
      expect(res.similar.length, 3);
      final exact = await api.resolve('코대원포르테시럽');
      expect(exact.best!.displayName, '코대원포르테시럽');
    });

    test('중간에만 겹치는 이름은 확정하지 않는다', () {
      expect(nameScore('클로르프로', '명인클로르프로마진염산염정') > 3, isTrue);
    });
  });

  test('DUR 성분정보 표에서 공식 연령 기준을 찾는다', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      expect(req.url.path, contains('DURIrdntInfoService03/getSpcifyAgrdeTabooInfoList02'));
      return http.Response.bytes(
          utf8.encode(jsonEncode({
            'header': {'resultCode': '00'},
            'body': {
              'items': [
                {'INGR_CODE': 'D000147', 'AGE_BASE': '12세 미만', 'DEL_YN': '정상'},
                {'INGR_CODE': 'D000254', 'AGE_BASE': '2세 미만', 'DEL_YN': '정상'},
              ]
            }
          })),
          200);
    });
    final api = DurApi('k', client: client);
    expect(await api.ingredientAgeBase('D000147'), '12세 미만');
    expect(await api.ingredientAgeBase('D000254'), '2세 미만');
    expect(await api.ingredientAgeBase('D999999'), '');
    expect(calls, 1); // 표는 한 번만 받는다
  });

  test('연령금기 기준은 가장 넓은 것 하나만 표시', () {
    final conds = [
      ...AgeRule.parse('12세 미만').conditions,
      ...AgeRule.parse('만 12세 이하').conditions,
    ];
    expect(AgeRule.summarize(conds), '12세 이하');
    expect(AgeRule.summarize(AgeRule.parse('6개월 미만').conditions), '6개월 미만');
    expect(
        AgeRule.summarize([
          ...AgeRule.parse('소아').conditions,
          ...AgeRule.parse('2세 미만').conditions,
        ]),
        '2세 미만');
  });

  test('한글 단어 단위 줄바꿈: 띄어쓰기는 그대로, 단어 안에는 결합자', () {
    final t = ka('약을 임의로 끊지 마세요');
    expect(t.split(' ').length, 4);
    expect(t.replaceAll('\u2060', ''), '약을 임의로 끊지 마세요');
    expect(t.contains('임\u2060의\u2060로'), isTrue);
  });

  test('성인 프로필 임신·수유 저장', () {
    final p = ChildProfile(
        id: '1', name: '엄마', birthDate: DateTime(1992, 3, 1), pregnant: true, nursing: false);
    final back = ChildProfile.fromJson(p.toJson());
    expect(back.pregnant, isTrue);
    expect(back.nursing, isFalse);
    expect(back.isAdult, isTrue);
    expect(ChildProfile(id: '2', name: '아기', birthDate: DateTime(2025, 1, 1)).isAdult, isFalse);
  });

  test('성분 병용금기 표 받기', () async {
    final client = MockClient((req) async {
      expect(req.url.path, contains('getUsjntTabooInfoList02'));
      final page = req.url.queryParameters['pageNo'];
      final items = page == '1'
          ? [
              {'INGR_KOR_NAME': '이트라코나졸', 'MIXTURE_INGR_KOR_NAME': '심바스타틴', 'PROHBT_CONTENT': '횡문근융해증'},
            ]
          : <Map<String, String>>[];
      return http.Response.bytes(
          utf8.encode(jsonEncode({'header': {'resultCode': '00'}, 'body': {'items': items}})), 200);
    });
    final t = await DurApi('k', client: client).ingredientMixTable();
    expect(t.single.a, '이트라코나졸');
    expect(t.single.b, '심바스타틴');
    expect(t.single.reason, '횡문근융해증');
  });

  test('처방 기록 저장 형식', () {
    final r = MedRecord(
        id: '1', childId: 'c', title: '9월 30일 처방', createdAt: DateTime(2026, 9, 30))
      ..drugs.addAll(['세토펜현탁액', '코푸시럽']);
    final back = MedRecord.fromJson(r.toJson());
    expect(back.title, '9월 30일 처방');
    expect(back.drugs, ['세토펜현탁액', '코푸시럽']);
    expect(MedRecord.defaultTitle(DateTime(2026, 9, 30)), '9월 30일 처방');
  });

  test('만 나이 개월 계산', () {
    expect(monthsBetween(DateTime(2021, 5, 20), DateTime(2026, 5, 19)), 59);
    expect(monthsBetween(DateTime(2021, 5, 20), DateTime(2026, 5, 20)), 60);
    expect(formatAge(62), '만 5세 2개월');
  });
}
