/// 설명서의 용법·용량 문장에서 복용자 나이에 맞는 부분만 짧게 골라낸다.
/// 새로 조회하지 않고 이미 받아 둔 설명서(e약은요·허가정보) 문장만 쓴다 (느려지지 않게).
library;

/// 나이 구간 (개월, 양 끝 포함)
class _Range {
  const _Range(this.lo, this.hi);
  final int lo;
  final int hi;
  bool has(int m) => m >= lo && m <= hi;
}

int _months(int n, String unit) => unit == '개월' ? n : n * 12;

final _rangeRe = RegExp(
    r'(?:만\s*)?(\d{1,2})\s*(개월|세)?\s*(?:[~\-∼〜]|부터)\s*(?:만\s*)?(\d{1,2})\s*(개월|세)\s*(미만|이하|까지)?');
final _boundRe = RegExp(r'(?:만\s*)?(\d{1,2})\s*(개월|세)\s*(이상|이하|미만|초과)');
final _adultRe = RegExp(r'성인');

/// 문장 조각에 적힌 나이 구간. 없으면 null.
_Range? _rangeOf(String s) {
  final m = _rangeRe.firstMatch(s);
  if (m != null) {
    final u2 = m.group(4)!;
    final u1 = m.group(2) ?? u2;
    final lo = _months(int.parse(m.group(1)!), u1);
    var hi = _months(int.parse(m.group(3)!), u2);
    // "7~14세"는 14세 11개월까지, "2세 미만"처럼 끝을 빼는 말이 있으면 그 전까지
    final tail = m.group(5);
    if (tail == '미만') {
      hi -= 1;
    } else if (u2 == '세') {
      hi += 11;
    }
    return _Range(lo, hi);
  }
  final b = _boundRe.firstMatch(s);
  if (b != null) {
    final v = _months(int.parse(b.group(1)!), b.group(2)!);
    return switch (b.group(3)) {
      '이상' => _Range(v, 1200),
      '초과' => _Range(v + (b.group(2) == '세' ? 12 : 1), 1200),
      '미만' => _Range(0, v - 1),
      _ => _Range(0, b.group(2) == '세' ? v + 11 : v), // 이하
    };
  }
  if (_adultRe.hasMatch(s)) return const _Range(15 * 12, 1200);
  return null;
}

/// 나이 구간이 시작되는 곳마다 끊어 조각으로 나눈다
List<String> _pieces(String text) {
  var t = text
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'[\r\n]+'), ' | ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // "성인 …, 소아 …" / "만 7~14세: …" 앞에서 끊는다
  t = t.replaceAllMapped(
      RegExp(r'(?=(?:만\s*)?\d{1,2}\s*(?:개월|세)?\s*(?:[~\-∼〜]|부터)\s*(?:만\s*)?\d{1,2}\s*(?:개월|세))|(?=성인)|(?=(?:만\s*)?\d{1,2}\s*(?:개월|세)\s*(?:이상|이하|미만|초과))'),
      (m) => ' | ');
  return t
      .split(RegExp(r'\s*(?:\||;|(?<=[다요])\.\s|○|●|■|□|▶)\s*'))
      .map((s) => s.trim().replaceAll(RegExp(r'^[,.\-:·\s]+|[,\s]+$'), ''))
      .where((s) => s.length >= 4)
      .toList();
}

/// 용량이 들어 있는 조각인지 (1회 몇 정·mL·번 등)
final _doseRe = RegExp(
    r'(\d|반|적당량|1/2)\s*(정|캡슐|포|mL|ml|㎖|밀리리터|mg|㎎|g|방울|회|번|스푼|병|매|칙|분무|펌프|알)');

String _short(String s, [int max = 60]) {
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.length <= max) return s;
  final cut = s.substring(0, max);
  final sp = cut.lastIndexOf(RegExp(r'[ ,]'));
  return '${(sp > max * 0.6 ? cut.substring(0, sp) : cut).trim()}…';
}

/// 복용자 나이([ageMonths])에 맞는 용량 한 줄. 설명서에 없으면 null.
/// 나이별 용량이 적혀 있는데 이 나이에 맞는 게 없으면 '설명서에 이 나이 용량 없음'을 알린다.
String? doseFor(String usage, int ageMonths) {
  if (usage.trim().isEmpty) return null;
  final ps = _pieces(usage);
  if (ps.isEmpty) return null;
  final ranged = <(String, _Range)>[];
  for (final p in ps) {
    final r = _rangeOf(p);
    if (r != null) ranged.add((p, r));
  }
  if (ranged.isEmpty) {
    // 나이 구분이 없는 설명서: 용량이 적힌 첫 조각
    final p = ps.firstWhere((p) => _doseRe.hasMatch(p), orElse: () => '');
    return p.isEmpty ? null : _short(p);
  }
  // 이 나이에 맞는 구간 중 가장 좁은 것 (예: "성인"보다 "12세 이상"보다 "7~14세")
  final hits = ranged.where((e) => e.$2.has(ageMonths) && _doseRe.hasMatch(e.$1)).toList()
    ..sort((a, b) => (a.$2.hi - a.$2.lo).compareTo(b.$2.hi - b.$2.lo));
  if (hits.isNotEmpty) return _short(hits.first.$1);
  return '설명서에 이 나이 용량이 없어요 · 의사·약사에게 확인';
}
