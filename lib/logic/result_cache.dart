/// 안전 확인 결과(약별 상세)를 앱이 켜져 있는 동안 보관한다.
/// 메인 화면에서 자동으로 확인한 기록을 '자세히 보기'로 열면 다시 조회하지 않고 바로 보여준다.
library;

import 'models.dart';

class ResultCache {
  static final _m = <String, (String, List<DrugCheck>)>{};

  /// 약 목록·복용자 정보가 같을 때만 같은 결과로 본다
  static String signature(MedRecord r, ChildProfile c) => [
        ...r.drugs,
        '#${c.birthDate.toIso8601String()}',
        '${c.ageInMonths(r.createdAt)}',
        '${c.pregnant}',
        '${c.nursing}',
        ...c.allergies,
      ].join('|');

  static List<DrugCheck>? get(MedRecord r, ChildProfile c) {
    final hit = _m[r.id];
    return hit != null && hit.$1 == signature(r, c) ? hit.$2 : null;
  }

  static void put(MedRecord r, ChildProfile c, List<DrugCheck> checks) =>
      _m[r.id] = (signature(r, c), checks);
}
