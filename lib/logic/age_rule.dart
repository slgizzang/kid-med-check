/// DUR 특정연령대금기 문구(예: "만 12세 미만의 소아")에서 연령 조건을 읽어
/// 아이 나이(개월)에 해당하는지 판단한다.
library;

enum AgeCmp { lt, le, ge, gt }

class AgeCondition {
  const AgeCondition(this.months, this.cmp, this.source);

  /// 기준 연령(개월 단위)
  final int months;
  final AgeCmp cmp;

  /// 원문에서 읽은 부분 (예: "12세 미만")
  final String source;

  bool get isUpperBound => cmp == AgeCmp.lt || cmp == AgeCmp.le;

  bool matches(int ageMonths) {
    switch (cmp) {
      case AgeCmp.lt:
        return ageMonths < months;
      case AgeCmp.le:
        // "2세 이하" = 만 2세 11개월까지 포함 (3세 생일 전까지)
        return months % 12 == 0 ? ageMonths < months + 12 : ageMonths <= months;
      case AgeCmp.ge:
        return ageMonths >= months;
      case AgeCmp.gt:
        return months % 12 == 0 ? ageMonths >= months + 12 : ageMonths > months;
    }
  }
}

class AgeRule {
  const AgeRule(this.conditions);

  final List<AgeCondition> conditions;

  bool get isParsed => conditions.isNotEmpty;

  static final RegExp _years =
      RegExp(r'(?:만\s*)?(\d{1,3})\s*세\s*(미만|이하|이상|초과)');
  static final RegExp _months = RegExp(r'(\d{1,3})\s*개월\s*(미만|이하|이상|초과)');

  static AgeCmp _cmpOf(String word) {
    switch (word) {
      case '미만':
        return AgeCmp.lt;
      case '이하':
        return AgeCmp.le;
      case '이상':
        return AgeCmp.ge;
      default:
        return AgeCmp.gt;
    }
  }

  static AgeRule parse(String text) {
    final conds = <AgeCondition>[];
    for (final m in _years.allMatches(text)) {
      conds.add(AgeCondition(
          int.parse(m.group(1)!) * 12, _cmpOf(m.group(2)!), m.group(0)!.trim()));
    }
    for (final m in _months.allMatches(text)) {
      conds.add(AgeCondition(
          int.parse(m.group(1)!), _cmpOf(m.group(2)!), m.group(0)!.trim()));
    }
    if (conds.isEmpty && text.contains('신생아')) {
      conds.add(const AgeCondition(1, AgeCmp.lt, '신생아'));
    }
    return AgeRule(conds);
  }

  /// true: 아이 나이가 금기 연령에 해당 / false: 해당 안 됨 / null: 판단 불가
  bool? appliesTo(int ageMonths) {
    if (conditions.isEmpty) return null;
    final uppers = conditions.where((c) => c.isUpperBound).toList();
    final lowers = conditions.where((c) => !c.isUpperBound).toList();

    if (uppers.isEmpty) return lowers.any((c) => c.matches(ageMonths));
    if (lowers.isEmpty) return uppers.any((c) => c.matches(ageMonths));

    // "6개월 이상 2세 미만"처럼 구간이면 AND, "12세 미만 및 65세 이상"처럼
    // 떨어진 두 범위면 OR로 본다.
    final isRange =
        lowers.every((l) => uppers.every((u) => l.months < u.months));
    if (isRange) {
      return lowers.any((c) => c.matches(ageMonths)) &&
          uppers.any((c) => c.matches(ageMonths));
    }
    return conditions.any((c) => c.matches(ageMonths));
  }
}
