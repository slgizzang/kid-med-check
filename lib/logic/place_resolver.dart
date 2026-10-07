/// 이름만 있는 병원·약국(심평원 투약이력에서 불러온 기록)의 정확한 위치·주소·코드를 찾는다.
/// 같은 이름이 전국에 여럿이어도, 처방 병원과 조제 약국은 보통 바로 옆에 있으므로
/// "서로 가장 가까운 병원·약국 짝"을 고른다. 내 위치를 알면 그것도 기준으로 쓴다.
library;

import 'dart:math' as math;

import 'dur_api.dart';
import 'models.dart';

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

/// 병원·약국 정하기 — 추측하지 않는다.
/// 심평원 자료에서 이름이 정확히 같은 기관이 딱 한 곳일 때만 그곳으로 정한다.
/// 같은 이름이 여러 곳이면 정하지 않고(null) 사용자가 주소를 보고 고르게 한다.
/// ([hospKnown]/[pharmKnown]/[me]는 예전 호출과 맞추기 위해 남겨 두지만 판정에 쓰지 않는다.)
PlacePair resolvePair({
  required List<PlaceHit> hosps,
  required List<PlaceHit> pharms,
  (double, double)? hospKnown,
  (double, double)? pharmKnown,
  (double, double)? me,
}) =>
    PlacePair(
      hospKnown == null && hosps.length == 1 ? hosps.first : null,
      pharmKnown == null && pharms.length == 1 ? pharms.first : null,
    );

/// 같은 이름 후보를 짝 기관(처방 병원 ↔ 조제 약국)에서 가까운 순으로 — 고르는 화면에서 참고용
List<PlaceHit> sortByPartner(List<PlaceHit> cands, (double, double)? partner) {
  if (partner == null) return cands;
  return [...cands]..sort((a, b) => meters(partner, posOf(a)!).compareTo(meters(partner, posOf(b)!)));
}

class PlacePair {
  const PlacePair(this.hospital, this.pharmacy);
  final PlaceHit? hospital;
  final PlaceHit? pharmacy;
}

/// 기록의 병원 이름 (직접 고른 이름, 없으면 기록 제목 "9월 21일 써니이비인후과의원"에서)
String hospitalNameOf(MedRecord r) {
  if (r.hospital.trim().isNotEmpty) return r.hospital.trim();
  final t = r.title
      .replaceFirst(RegExp(r'^\s*\d{1,2}월\s*\d{1,2}일\s*'), '')
      .replaceAll(RegExp(r'^(처방|약국 구입)$'), '')
      .trim();
  return RegExp(r'(의원|병원|센터|클리닉|보건소)').hasMatch(t) ? t : '';
}

/// 여러 기록의 병원·약국 위치·주소·코드를 한꺼번에 채운다 (아직 위치가 없는 것만).
/// - 같은 이름은 한 번만 심평원에 묻는다.
/// - 한 기록에서 정해진 병원 위치는 같은 병원의 다른 기록에서 약국을 고를 때도 쓴다.
/// 바뀐 기록 수를 돌려준다.
Future<int> fillPlaces(DurApi api, List<MedRecord> records,
    {(double, double)? me, void Function(int done, int total)? onProgress}) async {
  final todo = records
      .where((r) => !r.otc &&
          ((hospitalNameOf(r).length >= 2 && r.hospitalPos == null) ||
              (r.pharmacy.length >= 2 && r.pharmacyPos == null)))
      .toList();
  if (todo.isEmpty) return 0;

  // 1) 이름별 후보 (같은 이름은 한 번만)
  final hNames = {for (final r in todo) if (r.hospitalPos == null) hospitalNameOf(r)}..remove('');
  final pNames = {for (final r in todo) if (r.pharmacyPos == null) r.pharmacy}..remove('');
  final jobs = [for (final n in hNames) (n, false), for (final n in pNames) (n, true)];
  final cand = <(String, bool), List<PlaceHit>>{};
  var done = 0;
  for (var i = 0; i < jobs.length; i += 4) {
    final batch = jobs.skip(i).take(4).toList();
    final got = await Future.wait(batch.map((j) => sameName(api, j.$1, pharmacy: j.$2)));
    for (var k = 0; k < batch.length; k++) {
      cand[batch[k]] = got[k];
    }
    done += batch.length;
    onProgress?.call(done, jobs.length);
  }

  // 2) 병원 위치: 이미 아는 기록 → 짝으로 정해지는 기록 순서로 모은다
  final hospAt = <String, PlaceHit>{};
  final hospPos = <String, (double, double)>{
    for (final r in records)
      if (r.hospitalPos != null && hospitalNameOf(r).isNotEmpty) hospitalNameOf(r): r.hospitalPos!,
  };
  // 두 번 돌면, 첫 바퀴에 정해진 병원 위치로 두 번째 바퀴에서 약국을 더 고를 수 있다
  var changed = <MedRecord>{};
  for (var pass = 0; pass < 2; pass++) {
    for (final r in todo) {
      final hn = hospitalNameOf(r);
      final known = r.hospitalPos ?? hospPos[hn];
      final pair = resolvePair(
        hosps: known == null ? (cand[(hn, false)] ?? const []) : const [],
        pharms: r.pharmacyPos == null ? (cand[(r.pharmacy, true)] ?? const []) : const [],
        hospKnown: known,
        pharmKnown: r.pharmacyPos,
        me: me,
      );
      final h = pair.hospital ?? hospAt[hn];
      if (r.hospitalPos == null) {
        if (h != null && posOf(h) != null) {
          if (r.hospital.isEmpty) r.hospital = hn;
          if (r.hospitalAddr.isEmpty) r.hospitalAddr = h.addr;
          r.hospitalCode = h.code;
          r.hospitalPos = posOf(h);
          hospAt[hn] = h;
          hospPos[hn] = r.hospitalPos!;
          changed.add(r);
        } else if (known != null) {
          r.hospitalPos = known;
          changed.add(r);
        }
      }
      final ph = pair.pharmacy;
      if (r.pharmacyPos == null && ph != null && posOf(ph) != null) {
        if (r.pharmacyAddr.isEmpty) r.pharmacyAddr = ph.addr;
        r.pharmacyCode = ph.code;
        r.pharmacyPos = posOf(ph);
        changed.add(r);
      }
    }
  }
  return changed.length;
}
