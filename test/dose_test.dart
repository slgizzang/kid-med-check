import 'package:flutter_test/flutter_test.dart';
import 'package:kid_med_check/logic/dose.dart';

void main() {
  const syrup = '다음 1회 용량을 1일 3~4회 복용한다. 만 1~2세: 5 mL, 만 3~6세: 7.5 mL, 만 7~12세: 10 mL, '
      '만 13세 이상 및 성인: 15 mL';
  test('나이 구간별 용량에서 맞는 것만', () {
    expect(doseFor(syrup, 4 * 12), contains('7.5 mL'));
    expect(doseFor(syrup, 4 * 12), isNot(contains('10 mL')));
    expect(doseFor(syrup, 12 * 12 + 11), contains('10 mL'));
    expect(doseFor(syrup, 30 * 12), contains('15 mL'));
  });

  test('코 스프레이: 나이별 분무 횟수', () {
    const spray = '성인 및 12세 이상: 1회 1~2번씩 각 콧구멍에 1일 2~3회 분무한다. '
        '6~11세: 1회 1번씩 각 콧구멍에 1일 1~2회 분무한다. 6세 미만은 사용하지 않는다.';
    expect(doseFor(spray, 8 * 12), contains('1회 1번씩'));
    expect(doseFor(spray, 20 * 12), contains('1~2번씩'));
  });

  test('이 나이 용량이 없으면 알림', () {
    expect(doseFor('성인: 1회 1정, 1일 3회 식후 복용', 5 * 12), contains('이 나이 용량이 없어요'));
  });

  test('나이 구분이 없으면 첫 용량 문장', () {
    expect(doseFor('1일 1~2회 환부에 적당량을 바른다.', 60), contains('적당량'));
    expect(doseFor('', 60), isNull);
  });

  test('개월 단위', () {
    const s = '6개월~2세 미만: 1회 2.5mL, 2세~6세: 1회 5mL';
    expect(doseFor(s, 12), contains('2.5mL'));
    expect(doseFor(s, 36), contains('5mL'));
  });
}
