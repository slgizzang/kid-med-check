import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kid_med_check/logic/age_rule.dart';
import 'package:kid_med_check/logic/drug_name_extractor.dart';
import 'package:kid_med_check/logic/dur_api.dart';
import 'package:kid_med_check/logic/label_age.dart';
import 'package:kid_med_check/logic/similarity.dart';
import 'package:kid_med_check/logic/snapshot.dart';
import 'package:kid_med_check/ui/theme.dart';
import 'package:kid_med_check/logic/models.dart';
import 'package:kid_med_check/logic/reaction.dart';
import 'package:kid_med_check/logic/claim.dart';
import 'package:kid_med_check/logic/allergy.dart';
import 'package:kid_med_check/logic/report.dart';
import 'package:kid_med_check/logic/dur_text.dart';
import 'package:kid_med_check/logic/hira_import.dart';
import 'package:kid_med_check/logic/place_name.dart';
import 'package:kid_med_check/logic/office_decrypt.dart';

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

  test('효능은 명사 나열형으로', () {
    expect(efficacyPhrase('이 약은 기침, 가래에 사용합니다.'), '기침, 가래');
    expect(efficacyPhrase('이 약은 성인의 급·만성 설사, 24개월 이상 소아의 급성 설사에 사용합니다. 성인은 1회…'),
        '성인의 급·만성 설사, 24개월 이상 소아의 급성 설사');
    expect(efficacyPhrase(''), '');
  });

  test('문장마다 줄바꿈', () {
    expect(splitSentences('약국에 확인하세요. 의사가 처방했을 수도 있어요.'),
        '약국에 확인하세요.\n의사가 처방했을 수도 있어요.');
  });

  test('결과 스냅샷 저장·목록 변경 감지', () {
    final snap = ResultSnapshot(
      at: DateTime(2026, 9, 30, 16, 40),
      drugs: [
        DrugSnap(query: '코푸정', title: '코푸정', preg: true),
        DrugSnap(query: '세토펜', title: '세토펜현탁액'),
      ],
      mixPairs: const [],
      pregnant: true,
      nursing: false,
    );
    final r = MedRecord(id: '1', childId: 'c', title: 't', createdAt: DateTime(2026, 9, 30),
        drugs: ['코푸정', '세토펜'], last: snap);
    final back = MedRecord.fromJson(r.toJson());
    expect(back.last!.pregCount, 1);
    expect(back.last!.matches(['세토펜', '코푸정']), isTrue);
    expect(back.last!.matches(['세토펜', '코푸정', '타이레놀']), isFalse);
  });

  test('수유부 부분만 요약', () {
    const t = '이 약에 과민증 환자, 15세 미만의 소아는 이 약을 복용하지 마십시오.이 약을 복용하기 전에 '
        '알레르기 체질, 임부 또는 임신하고 있을 가능성이 있는 여성 및 수유부, 고령자는 의사 또는 약사와 상의하십시오.'
        '정해진 용법과 용량을 잘 지키십시오.';
    expect(nursingSummary(t), '수유부는 복용 전에 의사 또는 약사와 상의하도록 되어 있어요.');
    expect(nursingSummary('수유부는 이 약을 복용하지 마십시오.'), '수유부는 복용하지 않도록 되어 있어요.');
    expect(nursingSummary('정해진 용법을 지키십시오.'), isNull);
  });

  test('제형만 있는 이름은 약으로 받지 않음', () {
    expect(DrugNameExtractor.isFormOnly('패치'), isTrue);
    expect(DrugNameExtractor.isFormOnly('현탁액'), isTrue);
    expect(DrugNameExtractor.isFormOnly('레스날린패치'), isFalse);
  });

  test('병원·약국 검색 결과를 가까운 순으로', () async {
    final client = MockClient((req) async {
      expect(req.url.path, contains('getParmacyBasisList'));
      expect(req.url.queryParameters['yadmNm'], '온누리');
      return http.Response(
          jsonEncode({
            'response': {
              'header': {'resultCode': '00'},
              'body': {
                'items': {
                  'item': [
                    {'yadmNm': '먼온누리약국', 'addr': '부산', 'XPos': '129.07', 'YPos': '35.17'},
                    {'yadmNm': '가까운온누리약국', 'addr': '서울 강남구', 'XPos': '127.028', 'YPos': '37.498'},
                  ]
                }
              }
            }
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final hits = await DurApi('k', client: client)
        .searchPlaces('온누리', pharmacy: true, lat: 37.4979, lon: 127.0276);
    expect(hits.first.name, '가까운온누리약국');
    expect(hits.first.distanceLabel.endsWith('m'), isTrue);
    expect(hits.last.distanceLabel, contains('km'));
  });

  test('병원 공식 이름에서 법인 부분 떼기 (네이버 지도 검색용)', () {
    expect(searchablePlaceName('재단법인아산사회복지재단서울아산병원'), '서울아산병원');
    expect(searchablePlaceName('사회복지법인삼성생명공익재단삼성서울병원'), '삼성서울병원');
    expect(searchablePlaceName('학교법인가톨릭학원가톨릭대학교서울성모병원'), '가톨릭대학교서울성모병원');
    expect(searchablePlaceName('의료법인성광의료재단차병원'), '차병원');
    expect(searchablePlaceName('써니이비인후과의원'), '써니이비인후과의원');
    expect(searchablePlaceName('온누리약국'), '온누리약국');
  });

  test('처방 기록 저장 형식', () {
    final r = MedRecord(
        id: '1', childId: 'c', title: '9월 30일 처방', createdAt: DateTime(2026, 9, 30))
      ..drugs.addAll(['세토펜현탁액', '코푸시럽']);
    final back = MedRecord.fromJson(r.toJson());
    expect(back.title, '9월 30일 처방');
    expect(back.drugs, ['세토펜현탁액', '코푸시럽']);
    expect(MedRecord.defaultTitle(DateTime(2026, 9, 30)), '9월 30일 처방');
    expect(back.hospital, '');
    r.hospital = '써니이비인후과의원';
    r.claimed = true;
    final back2 = MedRecord.fromJson(r.toJson());
    expect(back2.hospital, '써니이비인후과의원');
    expect(back2.claimed, isTrue);
  });

  test('만 나이 개월 계산', () {
    expect(monthsBetween(DateTime(2021, 5, 20), DateTime(2026, 5, 19)), 59);
    expect(monthsBetween(DateTime(2021, 5, 20), DateTime(2026, 5, 20)), 60);
    expect(formatAge(62), '만 5세 2개월');
  });

  group('허가정보', () {
    test('허가정보 행을 제품으로 (한글 성분·구분·분류)', () {
      final h = ProductHit.fromPermit({
        'ITEM_NAME': '싱귤레어세립4밀리그램(몬테루카스트나트륨)',
        'ENTP_NAME': '한국오가논(주)',
        'SPCLTY_PBLC': '전문의약품',
        'PRDUCT_TYPE': '[01490]기타의 알레르기용약',
        'ITEM_INGR_NAME': 'Montelukast Sodium',
        'CANCEL_NAME': '정상',
      })!;
      expect(h.displayName, '싱귤레어세립4밀리그램');
      expect(h.searchName, '싱귤레어세립');
      expect(h.ingredient, '몬테루카스트나트륨');
      expect(h.etcOtc, '전문의약품');
      expect(h.className, '기타의 알레르기용약');
    });

    test('괄호 성분이 없으면 영문 성분(중복 제거), 취소 품목은 제외', () {
      expect(ProductHit.permitIngredient('어떤시럽', 'Tulobuterol/Tulobuterol'), 'Tulobuterol');
      expect(
          ProductHit.fromPermit({'ITEM_NAME': '옛날정', 'CANCEL_NAME': '취소'}), isNull);
    });

    test('DUR·e약은요에 없는 약도 허가정보로 찾는다', () async {
      final client = MockClient((req) async {
        var items = <Map<String, String>>[];
        if (req.url.path.contains('getDrugPrdtPrmsnInq08') &&
            (req.url.queryParameters['item_name'] ?? '').contains('레스날린')) {
          items = [
            {
              'ITEM_NAME': '레스날린패취0.5밀리그램(툴로부테롤)',
              'SPCLTY_PBLC': '전문의약품',
              'ITEM_INGR_NAME': 'Tulobuterol/Tulobuterol',
              'CANCEL_NAME': '정상',
            },
          ];
        }
        return http.Response.bytes(
            utf8.encode(jsonEncode({'header': {'resultCode': '00'}, 'body': {'items': items}})),
            200);
      });
      final res = await DurApi('k', client: client).resolve('레스날린패취');
      expect(res.best, isNotNull);
      expect(res.best!.ingredient, '툴로부테롤');
      expect(res.best!.etcOtc, '전문의약품');
    });
  });

  group('복용 후 반응 기록', () {
    final note = ReactionNote(
      id: '1',
      childId: 'c',
      drug: '세토펜현탁액',
      ingredient: '아세트아미노펜',
      date: DateTime(2026, 3, 12),
      symptoms: ['설사'],
      memo: '2번',
    );

    test('같은 약·같은 성분을 알아본다', () {
      expect(matchReaction(note, '세토펜현탁액(아세트아미노펜)', ''), ReactionMatch.sameDrug);
      expect(matchReaction(note, '챔프시럽', '아세트아미노펜'), ReactionMatch.sameIngredient);
      expect(matchReaction(note, '맥시부펜시럽', '덱시부프로펜'), isNull);
      expect(note.summary, '설사 · 2번');
    });

    test('처방 전체 기록은 함께 먹은 약 중 하나라도 다시 나오면 알려준다', () {
      final g = ReactionNote(
        id: '2',
        childId: 'c',
        drug: '3월 12일 처방',
        date: DateTime(2026, 3, 12),
        symptoms: ['설사'],
        items: [('세토펜현탁액', '아세트아미노펜'), ('코대원에스시럽', '')],
      );
      expect(matchReaction(g, '코대원에스시럽', ''), ReactionMatch.sameDrug);
      expect(matchReaction(g, '챔프시럽', '아세트아미노펜'), ReactionMatch.sameIngredient);
      expect(matchReaction(g, '맥시부펜시럽', '덱시부프로펜'), isNull);
      expect(reactionLine(g, ReactionMatch.sameDrug), contains('함께 먹은 약(세토펜현탁액, 코대원에스시럽)'));
      final back = ReactionNote.fromJson(g.toJson());
      expect(back.items.length, 2);
      expect(back.isGroup, isTrue);
    });

    test('저장 형식', () {
      final back = ReactionNote.fromJson(note.toJson());
      expect(back.drug, '세토펜현탁액');
      expect(back.symptoms, ['설사']);
      expect(back.date, DateTime(2026, 3, 12));
    });

    test('스냅샷에 반응 기록이 남는다', () {
      final d = DrugSnap(query: 'a', title: 'a', reaction: '설사');
      final back = DrugSnap.fromJson(d.toJson());
      expect(back.reaction, '설사');
      expect(back.hasAlert, isFalse);
      expect(back.hasAny, isTrue);
    });
  });

  group('심평원 투약이력 불러오기', () {
    final bytes = File('test/fixtures/hira_sample.xlsx').readAsBytesSync();

    test('암호화된 엑셀을 생년월일로 자동으로 연다', () {
      expect(OfficeDecrypt.kindOf(bytes), OfficeKind.encryptedXlsx);
      final r = HiraImport.open(bytes, people: [
        ('아이', DateTime(2024, 1, 1)),
        ('엄마', DateTime(1990, 1, 1)),
      ]);
      expect(r.passwordOwner, '엄마');
      expect(r.visits.length, 2);
      final may = r.visits.first;
      expect(may.date, DateTime(2026, 5, 2));
      expect(may.place, '바른이비인후과');
      expect(may.drugs, ['싱귤레어세립4밀리그램']);
      final mar = r.visits.last;
      expect(mar.drugs, ['세토펜현탁액', '코대원에스시럽']);
      expect(mar.title, '3월 12일 튼튼소아청소년과의원');
    });

    test('비밀번호가 틀리면 직접 입력을 요청한다', () {
      expect(
          () => HiraImport.open(bytes, people: [('아이', DateTime(2024, 1, 1))]),
          throwsA(isA<OfficeFileException>()
              .having((e) => e.wrongPassword, 'wrongPassword', isTrue)));
      final r = HiraImport.open(bytes, manualPassword: '19900101');
      expect(r.visits.length, 2);
    });

    test('공유 문자열·엑셀 날짜·병합 칸도 읽는다', () {
      final plain = File('test/fixtures/hira_shared.xlsx').readAsBytesSync();
      expect(OfficeDecrypt.kindOf(plain), OfficeKind.plainXlsx);
      final r = HiraImport.open(plain);
      expect(r.visits.length, 1);
      expect(r.visits.first.date, DateTime(2026, 3, 12));
      expect(r.visits.first.place, '튼튼의원');
      expect(r.visits.first.drugs, ['세토펜현탁액', '맥시부펜시럽']);
    });

    test('처방 병원과 조제 약국을 따로 읽는다 (실손 병원비·약값 청구용)', () {
      final plain = File('test/fixtures/hira_shared.xlsx').readAsBytesSync();
      final v = HiraImport.open(plain).visits.first;
      expect(v.hospital, '튼튼의원');
      expect(v.pharmacy, '행복약국');

      final rows = [
        ['조제일자', '처방기관', '조제기관', '제품명'],
        ['2026-10-01', '바른소아청소년과의원', '온누리약국', '세토펜현탁액'],
        ['', '', '', '코푸시럽'],
      ];
      final w = HiraImport.parseRows(rows).single;
      expect(w.hospital, '바른소아청소년과의원');
      expect(w.pharmacy, '온누리약국');
      expect(w.drugs, ['세토펜현탁액', '코푸시럽']);
    });

    test('날짜 형식', () {
      expect(HiraImport.parseDate('2026.3.12'), DateTime(2026, 3, 12));
      expect(HiraImport.parseDate('20260312'), DateTime(2026, 3, 12));
      expect(HiraImport.parseDate('46093'), DateTime(2026, 3, 12));
      expect(HiraImport.passwordsFor(DateTime(1990, 1, 1)), ['19900101', '900101']);
    });
  });

  test('DUR 금기 사유 문장 나누기와 용어 풀이', () {
    expect(friendlyTaboo('임부에 대한 안전성 미확립 랫트 태자에서 짧은 과잉목갈비뼈 증가 보고'),
        '임부에 대한 안전성 미확립. (동물실험) 쥐 태아에서 짧은 과잉목갈비뼈 증가 보고.');
    expect(friendlyTaboo('태아 기형 유발 가능성'), '태아 기형 유발 가능성.');
    expect(friendlyTaboo('포함 제제 투여 금지'), '포함 제제 투여 금지.');
  });

  test('설명서 금지 문구는 문장 끝까지', () {
    final f = LabelAge.check('2세 미만 영아는 이 약을 복용하지 마십시오. 기타', 20)!;
    expect(f.evidence, '2세 미만 영아는 이 약을 복용하지 마십시오');
    expect(f.prohibited, isTrue);
  });

  test('허가정보 설명서 XML을 글로', () {
    const xml = '<DOC title="효능효과" type="EE">\r\n <SECTION title="">\r\n <ARTICLE title="">\r\n'
        '<PARAGRAPH tagName="p" textIndent="0" marginLeft="0"><![CDATA[습진, 피부염, 건선]]></PARAGRAPH>'
        '</ARTICLE></SECTION></DOC>';
    expect(DurApi.docText(xml), '습진, 피부염, 건선');
    expect(DurApi.docText(''), '');
  });

  test('복용 리포트: 계열·약·반응 패턴 집계와 생활 관리 참고', () {
    MedRecord rec(String id, DateTime d, List<String> drugs) =>
        MedRecord(id: id, childId: 'c', title: id, createdAt: d, drugs: drugs);
    final records = [
      rec('1', DateTime(2026, 3, 12), ['세토펜현탁액', '오구멘틴듀오시럽']),
      rec('2', DateTime(2026, 5, 2), ['세토펜현탁액', '클래신건조시럽']),
      rec('3', DateTime(2026, 9, 1), ['코대원에스시럽']),
    ];
    final notes = [
      ReactionNote(id: 'a', childId: 'c', drug: '처방', date: DateTime(2026, 3, 13),
          symptoms: ['설사'], items: [('세토펜현탁액', ''), ('오구멘틴듀오시럽', '')]),
      ReactionNote(id: 'b', childId: 'c', drug: '세토펜현탁액', date: DateTime(2026, 5, 3),
          symptoms: ['설사']),
    ];
    final meta = {
      '세토펜현탁액': const DrugMeta(cls: '[01140]해열.진통.소염제'),
      '오구멘틴듀오시럽': const DrugMeta(cls: '주로 그람양성, 음성균에 작용하는 것'),
      '클래신건조시럽': const DrugMeta(cls: '기타의 항생물질제제'),
    };
    final r = buildReport(records, notes, meta, now: DateTime(2026, 10, 1));
    expect(r.records, 3);
    expect(r.drugKinds, 4);
    expect(r.topDrugs.first.name, '세토펜현탁액');
    expect(r.topDrugs.first.count, 2);
    expect(r.topClasses.first.name, '해열·진통·소염제');
    final p = r.patterns.first;
    expect(p.drug, '세토펜현탁액');
    expect(p.symptom, '설사');
    expect(p.times, 2);
    expect(p.taken, 2);
    expect(p.withOthers, isTrue);
    expect(r.tips.map((t) => t.title), contains('유산균(프로바이오틱스)'));
    expect(r.unknownClass, ['코대원에스시럽']);
    expect(r.monthly.length, 12);
    expect(r.monthly.last.$1, DateTime(2026, 10));
  });

  test('이후에 적은 반응은 이전 기록에 지난 반응으로 나오지 않는다', () {
    final later = ReactionNote(
        id: 'x', childId: 'c', recordId: 'r2', drug: '세토펜현탁액',
        date: DateTime(2026, 9, 1), symptoms: ['설사']);
    final notes = [later];
    // 3월 기록에서 보면: 9월에 적은 반응은 빠진다
    expect(reactionsFor(notes, '세토펜현탁액', '', recordId: 'r1', before: DateTime(2026, 3, 1)),
        isEmpty);
    // 10월 기록에서 보면: 지난 반응으로 나온다
    expect(reactionsFor(notes, '세토펜현탁액', '', recordId: 'r3', before: DateTime(2026, 10, 1)).length,
        1);
    // 그 반응을 적은 기록 자신: 결과 화면에선 빼고, 목록에선 이번 반응으로
    expect(reactionsFor(notes, '세토펜현탁액', '', recordId: 'r2', before: DateTime(2026, 9, 1)),
        isEmpty);
    expect(reactionsFor(notes, '세토펜현탁액', '',
            recordId: 'r2', before: DateTime(2026, 9, 1), includeOwn: true).length,
        1);
  });

  test('반응 요약: 횟수·비율만, 차이가 뚜렷할 때만 비교', () {
    final records = <MedRecord>[];
    final notes = <ReactionNote>[];
    for (var i = 0; i < 10; i++) {
      final hasA = i < 4;
      records.add(MedRecord(
          id: 'r$i', childId: 'c', title: 't', createdAt: DateTime(2026, 1, i + 1),
          drugs: [if (hasA) '에이시럽', '비시럽']));
      if (i < 3) {
        notes.add(ReactionNote(id: 'n$i', childId: 'c', recordId: 'r$i', drug: 't',
            date: DateTime(2026, 1, i + 2), symptoms: ['설사'],
            items: [if (hasA) ('에이시럽', ''), ('비시럽', '')]));
      }
    }
    final ins = symptomInsights(records, notes);
    final d = ins.single;
    expect(d.symptom, '설사');
    expect(d.records, 3);
    expect(d.totalRecords, 10);
    expect(d.contrast!.$1, '에이시럽');
    expect(d.contrast!.$2, 3); // 에이시럽 들어간 4번 중 3번
    expect(d.contrast!.$3, 4);
    expect(d.contrast!.$4, 0); // 안 들어간 6번 중 0번
    expect(withJosa('설사', '이', '가'), '설사가');
    expect(withJosa('발진', '이', '가'), '발진이');
  });

  test('알레르기 약물: 같은 계열·성분 찾기', () {
    expect(allergyHits(['페니실린계'], '오구멘틴듀오시럽', '아목시실린수화물, 클라불란산칼륨', '').single.matched,
        '아목시실린');
    expect(allergyHits(['페니실린'], '어떤약', 'Amoxicillin Hydrate', '').length, 1);
    expect(allergyHits(['세파계'], '오메프시럽', '세프디니르', '').length, 1);
    expect(allergyHits(['페니실린계'], '세토펜현탁액', '아세트아미노펜', ''), isEmpty);
    expect(allergyHits(['이부프로펜'], '맥시부펜시럽', '덱시부프로펜', ''), isEmpty); // 성분 직접 입력은 같은 성분만
    expect(allergyHits(['소염진통제(NSAIDs)'], '맥시부펜시럽', '덱시부프로펜', '').length, 1);
    final p = ChildProfile(id: 'a', name: 'n', birthDate: DateTime(2024), allergies: ['페니실린계']);
    expect(ChildProfile.fromJson(p.toJson()).allergies, ['페니실린계']);
  });

  test('약국 영수증에서 날짜·약국·본인부담금 읽기', () {
    const t = '약제비 계산서·영수증\n행복약국\n조제일자 2026-03-12\n총액 12,400\n본인부담금\n3,700원\n';
    final c = parseReceipt(t);
    expect(c.pharmacy, '행복약국');
    expect(c.date, DateTime(2026, 3, 12));
    expect(c.amount, 3700);
    expect(formatWon(12400), '12,400원');
  });

  test('처방전 약품코드 뒤 이름도 후보로', () {
    final names = DrugNameExtractor.extract('644900310 세토펜 \n 1회 3회 3일');
    expect(names, contains('세토펜'));
  });

  test('반응 요약: 이름이 달라도 같은 성분·계열로 묶어 본다', () {
    final records = [
      MedRecord(id: 'a', childId: 'c', title: 't', createdAt: DateTime(2026, 1, 1), drugs: ['오구멘틴시럽']),
      MedRecord(id: 'b', childId: 'c', title: 't', createdAt: DateTime(2026, 2, 1), drugs: ['아모크라시럽']),
      MedRecord(id: 'd', childId: 'c', title: 't', createdAt: DateTime(2026, 3, 1), drugs: ['세토펜현탁액']),
      MedRecord(id: 'e', childId: 'c', title: 't', createdAt: DateTime(2026, 4, 1), drugs: ['세토펜현탁액']),
    ];
    final notes = [
      ReactionNote(id: '1', childId: 'c', recordId: 'a', drug: '오구멘틴시럽', date: DateTime(2026, 1, 2), symptoms: ['설사']),
      ReactionNote(id: '2', childId: 'c', recordId: 'b', drug: '아모크라시럽', date: DateTime(2026, 2, 2), symptoms: ['설사']),
    ];
    final meta = {
      '오구멘틴시럽': const DrugMeta(cls: '주로 그람양성균에 작용하는 것', ingredient: '아목시실린수화물, 클라불란산칼륨'),
      '아모크라시럽': const DrugMeta(cls: '주로 그람양성균에 작용하는 것', ingredient: '아목시실린'),
      '세토펜현탁액': const DrugMeta(cls: '해열.진통.소염제', ingredient: '아세트아미노펜'),
    };
    final d = symptomInsights(records, notes, meta).single;
    final kinds = {for (final x in d.dims) x.kind: x};
    expect(kinds.containsKey('약'), isFalse); // 약 이름은 달라서 2번 겹치는 약 없음
    expect(kinds['성분']!.inSym, 2);
    expect(kinds['성분']!.name, startsWith('아목시실린'));
    expect(kinds['계열']!.name, '주로 그람양성균에 작용하는 것');
    expect(kinds['계열']!.withoutSym, 0);
  });
}
