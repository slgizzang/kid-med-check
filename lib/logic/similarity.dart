/// 약 이름 유사도: 한글을 자모(초성·중성·종성)로 풀어 편집 거리를 잰다.
/// "포타갤"처럼 모음 하나 틀린 오타도 "포타겔현탁액"을 가장 가깝게 찾도록.
library;

List<int> toJamo(String s) {
  final out = <int>[];
  for (final r in s.runes) {
    if (r >= 0xAC00 && r <= 0xD7A3) {
      final i = r - 0xAC00;
      out.add(0x1100 + i ~/ 588); // 초성
      out.add(0x1161 + (i % 588) ~/ 28); // 중성
      final jong = i % 28;
      if (jong != 0) out.add(0x11A7 + jong); // 종성
    } else {
      out.add(r);
    }
  }
  return out;
}

int editDistance(List<int> a, List<int> b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost]
          .reduce((x, y) => x < y ? x : y);
    }
    final t = prev;
    prev = cur;
    cur = t;
  }
  return prev[b.length];
}

/// 작을수록 비슷함. 0 = 같은 이름.
/// 입력이 약 이름 앞부분만일 때(예: "타이레놀")도 잘 맞도록, 앞부분 거리와 전체 거리 중 작은 값을 쓴다.
double nameScore(String query, String candidate) {
  if (query == candidate) return 0;
  final q = toJamo(query);
  final c = toJamo(candidate);
  final prefix = c.length > q.length ? c.sublist(0, q.length) : c;
  final prefixDist = editDistance(q, prefix) * 2.0 + (c.length - q.length).abs() * 0.05;
  final fullDist = editDistance(q, c).toDouble();
  final base = prefixDist < fullDist ? prefixDist : fullDist;
  // 이름 중간에만 들어 있는 경우(예: "클로르프로" → "명인클로르프로마진정")는
  // 후보로는 좋지만 "정확히 찾았다"고 하기엔 부족하므로 4점대로 둔다.
  if (candidate.contains(query) && !candidate.startsWith(query)) {
    final mid = 4 + (c.length - q.length).abs() * 0.02;
    return mid < base ? mid : base;
  }
  return base;
}
