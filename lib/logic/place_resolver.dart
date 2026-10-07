/// 이름만 있는 병원·약국(심평원 투약이력에서 불러온 기록)의 정확한 위치·주소·코드를 찾는다.
/// 같은 이름이 전국에 여럿이어도, 처방 병원과 조제 약국은 보통 바로 옆에 있으므로
/// "서로 가장 가까운 병원·약국 짝"을 고른다. 내 위치를 알면 그것도 기준으로 쓴다.
library;

import 'dart:math' as math;

import 'dur_api.dart';

double meters((double, double) a, (double, double) b) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.$1 - a.$1), dLon = rad(b.$2 - a.$2);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(a.$1)) * math.cos(rad(b.$1)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.asin(math.sqrt(h));
}

String _n(String s) => s.replaceAll(RegExp(r'\s'), '');

(double, double)? posOf(PlaceHit h) => h.lat != null && h.lng != null ? (h.lat!, h.lng!) : null;

/// 이름이 정확히 같은 심평원 기관들
Future<List<PlaceHit>> sameName(DurApi api, String name, {required bool pharmacy}) async {
  if (_n(name).length < 2) return const [];
  try {
    final hits = await api.searchPlaces(name, pharmacy: pharmacy, rows: 100);
    return hits.where((h) => _n(h.name) == _n(name) && posOf(h) != null).toList();
  } catch (_) {
    return const [];
  }
}

/// 후보 중 기준점에서 확실히 가장 가까운 곳 (5km 안, 두 번째보다 2배 이상 가까움)
PlaceHit? nearestClear(List<PlaceHit> cands, (double, double) p) {
  if (cands.isEmpty) return null;
  final s = [...cands]..sort((a, b) => meters(p, posOf(a)!).compareTo(meters(p, posOf(b)!)));
  final d0 = meters(p, posOf(s[0])!);
  if (d0 > 5000) return null;
  if (s.length == 1) return s[0];
  final d1 = meters(p, posOf(s[1])!);
  return d1 >= d0 * 2 ? s[0] : null;
}

/// 병원·약국 짝 찾기. 이미 위치를 아는 쪽은 [hospKnown]/[pharmKnown]로 넘긴다.
/// 돌려주는 값: (병원, 약국) — 정할 수 없으면 null.
PlacePair resolvePair({
  required List<PlaceHit> hosps,
  required List<PlaceHit> pharms,
  (double, double)? hospKnown,
  (double, double)? pharmKnown,
  (double, double)? me,
}) {
  PlaceHit? h, p;
  // 1) 한쪽 위치를 이미 알면 다른 쪽은 그 근처
  if (hospKnown != null) p = nearestClear(pharms, hospKnown);
  if (pharmKnown != null) h = nearestClear(hosps, pharmKnown);
  // 2) 둘 다 모르면: 서로 가장 가까운 짝 (1km 안, 다음 짝보다 확실히 가까움)
  if (h == null && p == null && hospKnown == null && pharmKnown == null &&
      hosps.isNotEmpty && pharms.isNotEmpty) {
    final pairs = <(PlaceHit, PlaceHit, double)>[
      for (final a in hosps)
        for (final b in pharms) (a, b, meters(posOf(a)!, posOf(b)!)),
    ]..sort((x, y) => x.$3.compareTo(y.$3));
    final best = pairs.first;
    final next = pairs.length > 1 ? pairs[1] : null;
    final clear = next == null ||
        // 두 번째 짝이 같은 병원(또는 약국)을 공유하면 그 쪽은 확정
        next.$3 >= best.$3 * 2 ||
        next.$3 - best.$3 > 500;
    if (best.$3 < 1000 && clear) {
      h = best.$1;
      p = best.$2;
    } else if (best.$3 < 1000 && next != null && identical(next.$1, best.$1)) {
      h = best.$1; // 병원은 확정, 약국은 아래에서 다시
    }
  }
  // 3) 하나뿐이면 그곳, 아니면 내 위치 기준
  h ??= hospKnown == null
      ? (hosps.length == 1 ? hosps.first : (me != null ? nearestClear(hosps, me) : null))
      : null;
  final hp = h != null ? posOf(h) : hospKnown;
  p ??= pharmKnown == null
      ? (pharms.length == 1
          ? pharms.first
          : (hp != null ? nearestClear(pharms, hp) : (me != null ? nearestClear(pharms, me) : null)))
      : null;
  return PlacePair(h, p);
}

class PlacePair {
  const PlacePair(this.hospital, this.pharmacy);
  final PlaceHit? hospital;
  final PlaceHit? pharmacy;
}
