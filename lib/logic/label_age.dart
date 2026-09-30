/// e약은요 설명문(효능·용법·주의사항)에서 "24개월 이상 소아", "2~6세", "성인 및 15세 이상",
/// "2세 미만은 복용하지 마십시오" 같은 사용 연령 문구를 읽는다.
/// DUR 연령금기와는 별개로, 설명서상 권장 연령보다 어린 경우를 잡아내기 위한 것.
library;

class LabelAgeFinding {
  const LabelAgeFinding({
    required this.months,
    required this.evidence,
    required this.prohibited,
  });

  /// 기준 연령(개월). 아이가 이보다 어리면 해당.
  final int months;

  /// 설명문에서 근거가 된 문구
  final String evidence;

  /// true: "~미만은 복용하지 마십시오" 같은 금지 문구 / false: "~이상 소아에 사용" 같은 사용 연령
  final bool prohibited;
}

class LabelAge {
  static const _child = r'(?:소아|어린이|유아|영아|아동|청소년|아이)';

  /// "24개월 이상 소아", "2세 이상의 소아"
  static final RegExp _lowerChild =
      RegExp(r'(?:만\s*)?(\d{1,2})\s*(세|개월)\s*이상\s*(?:의\s*)?' + _child);

  /// "15세 이상 및 성인", "성인 및 15세 이상"
  static final RegExp _lowerAdultA =
      RegExp(r'(?:만\s*)?(\d{1,2})\s*(세)\s*이상\s*(?:및|과|또는)?\s*성인');
  static final RegExp _lowerAdultB =
      RegExp(r'성인\s*(?:및|과|또는)\s*(?:만\s*)?(\d{1,2})\s*(세)\s*이상');

  /// "2~6세", "6~11개월"
  static final RegExp _range =
      RegExp(r'(?:만\s*)?(\d{1,2})\s*(?:세|개월)?\s*[~∼～\-]\s*\d{1,2}\s*(세|개월)');

  /// "2세 미만의 영아는 복용하지 마십시오", "6개월 미만에는 투여하지 않는다"
  static final RegExp _prohibit = RegExp(
      r'(?:만\s*)?(\d{1,2})\s*(세|개월)\s*(미만|이하)[^.。]{0,25}?(?:복용|투여|사용|먹이)(?:하지|해서는|하면 안)');

  static int _months(String n, String unit) =>
      unit == '개월' ? int.parse(n) : int.parse(n) * 12;

  /// 아이 나이(개월)가 설명서상 연령보다 어리면 그 근거를, 아니면 null.
  static LabelAgeFinding? check(String text, int ageMonths) {
    if (text.trim().isEmpty) return null;

    // 1) 명시적 금지 문구가 가장 강하다.
    for (final m in _prohibit.allMatches(text)) {
      var months = _months(m.group(1)!, m.group(2)!);
      // "2세 이하" = 3세 생일 전까지
      if (m.group(3) == '이하') {
        months = m.group(2) == '세' ? months + 12 : months + 1;
      }
      if (ageMonths < months) {
        return LabelAgeFinding(
            months: months, evidence: m.group(0)!.trim(), prohibited: true);
      }
    }

    // 2) 사용 연령 하한: 여러 개면 가장 낮은 연령 기준
    int? minMonths;
    String? evidence;
    void consider(int months, String ev) {
      if (minMonths == null || months < minMonths!) {
        minMonths = months;
        evidence = ev.trim();
      }
    }

    for (final m in _lowerChild.allMatches(text)) {
      consider(_months(m.group(1)!, m.group(2)!), m.group(0)!);
    }
    for (final re in [_lowerAdultA, _lowerAdultB]) {
      for (final m in re.allMatches(text)) {
        consider(_months(m.group(1)!, m.group(2)!), m.group(0)!);
      }
    }
    for (final m in _range.allMatches(text)) {
      consider(_months(m.group(1)!, m.group(2)!), m.group(0)!);
    }

    if (minMonths != null && ageMonths < minMonths!) {
      return LabelAgeFinding(
          months: minMonths!, evidence: evidence!, prohibited: false);
    }
    return null;
  }
}
