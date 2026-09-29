import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kid_med_check/logic/age_rule.dart';
import 'package:kid_med_check/logic/drug_name_extractor.dart';
import 'package:kid_med_check/logic/dur_api.dart';
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
      expect(AgeRule.parse('소아').appliesTo(60), isNull);
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

  test('만 나이 개월 계산', () {
    expect(monthsBetween(DateTime(2021, 5, 20), DateTime(2026, 5, 19)), 59);
    expect(monthsBetween(DateTime(2021, 5, 20), DateTime(2026, 5, 20)), 60);
    expect(formatAge(62), '만 5세 2개월');
  });
}
