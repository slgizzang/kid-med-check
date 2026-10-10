import 'package:flutter_test/flutter_test.dart';
import 'package:kid_med_check/logic/dur_api.dart';

void main() {
  test('지역 + 병원 이름', () {
    final q = splitPlaceQuery('강남구 아이사랑소아과의원');
    expect(q.name, '아이사랑소아과의원');
    expect(q.regions, ['강남구']);
    expect(q.dong, isNull);
  });
  test('이름 + 지역 (뒤에 붙여도)', () {
    final q = splitPlaceQuery('아이사랑소아과 부산');
    expect(q.name, '아이사랑소아과');
    expect(q.regions, ['부산']);
  });
  test('동 + 종류', () {
    final q = splitPlaceQuery('역삼동 소아과');
    expect(q.name, '소아과');
    expect(q.dong, '역삼동');
  });
  test('주소만', () {
    final q = splitPlaceQuery('서울 강남구 역삼동');
    expect(q.name, '');
    expect(q.dong, '역삼동');
    expect(q.regions, ['서울', '강남구']);
  });
  test('동 이름 하나만', () {
    final q = splitPlaceQuery('역삼동');
    expect(q.name, '');
    expect(q.dong, '역삼동');
  });
  test('이름만이면 그대로', () {
    final q = splitPlaceQuery('써니이비인후과');
    expect(q.name, '써니이비인후과');
    expect(q.regions, isEmpty);
    expect(q.dong, isNull);
  });
  test('주소 대조', () {
    expect(addrHasRegion('서울특별시 강남구 역삼로 1', '강남'), isTrue);
    expect(addrHasRegion('서울특별시 강남구 역삼로 1', '강남구'), isTrue);
    expect(addrHasRegion('서울특별시 강남구 역삼로 1', '서울'), isTrue);
    expect(addrHasRegion('부산광역시 해운대구', '강남'), isFalse);
  });
}
