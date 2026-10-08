/// 이름만 있는 병원·약국(심평원 투약이력에서 불러온 기록)의 정확한 위치·주소·코드를 찾는다.
/// 같은 이름이 전국에 여럿이어도, 처방 병원과 조제 약국은 보통 바로 옆에 있으므로
/// "서로 가장 가까운 병원·약국 짝"을 고른다. 내 위치를 알면 그것도 기준으로 쓴다.
library;

import 'dart:math' as math;

import 'dur_api.dart';
import 'hira_import.dart';
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

/// 처방 병원과 조제 약국은 한 세트: 한쪽이 정확히 정해지면 다른 쪽은 이 거리 안에서만 찾는다.
const kPairRadius = 1000.0;

/// 둘 다 흔한 이름일 때: 서로 이 거리 안에 붙어 있는 병원·약국 짝이 딱 하나면 그 짝
const kTwinRadius = 500.0;

/// 둘 다 흔한 이름일 때 병원 후보를 이만큼까지만 살펴본다 (조회가 너무 많아지지 않게)
const kTwinMaxHosp = 30;

/// [anchor] 주변 [kPairRadius] 안에서 이름이 정확히 같은 기관들 (심평원 주변 검색)
Future<List<PlaceHit>> sameNameNear(DurApi api, String name, (double, double) anchor,
    {required bool pharmacy, double radius = kPairRadius}) async {
  if (_n(name).length < 2) return const [];
  try {
    final hits = await api.searchPlaces('',
        pharmacy: pharmacy,
        lat: anchor.$1,
        lon: anchor.$2,
        radius: radius.round(),
        rows: 300);
    return hits
        .where((h) =>
            _n(h.name) == _n(name) && posOf(h) != null && meters(anchor, posOf(h)!) <= radius)
        .toList();
  } catch (_) {
    return const [];
  }
}

/// 여러 기록의 병원·약국 위치·주소·코드를 한꺼번에 채운다 (아직 위치가 없는 것만). 추측하지 않는다:
/// 1) 심평원 전체에서 이름이 정확히 한 곳뿐이면 그곳
/// 2) 짝(병원↔약국) 중 한쪽이 정해졌으면, 그 주변 1km 안에 같은 이름이 딱 한 곳일 때 그곳
/// 3) 같은 사람의 기록에서 이미 정해진 같은 이름(약국은 같은 병원 옆의 같은 이름)은 같은 곳
/// 바뀐 기록 수를 돌려준다.
Future<int> fillPlaces(DurApi api, List<MedRecord> records,
    {(double, double)? me, void Function(int done, int total)? onProgress}) async {
  // 예전에 불러온 기록 중 조제기관이 병원 자신인 것(원내 조제)은 약국이 아님
  final fixed = <MedRecord>{};
  for (final r in records) {
    if (!r.inHouse && r.imported && r.pharmacy.isNotEmpty &&
        HiraImport.isInHouse(hospitalNameOf(r), r.pharmacy)) {
      r.inHouse = true;
      r.pharmacy = '';
      r.pharmacyAddr = '';
      r.pharmacyCode = '';
      r.pharmacyPos = null;
      fixed.add(r);
    }
  }
  bool needH(MedRecord r) => hospitalNameOf(r).length >= 2 && r.hospitalPos == null;
  bool needP(MedRecord r) => r.pharmacy.length >= 2 && r.pharmacyPos == null;
  final todo = records.where((r) => !r.otc && (needH(r) || needP(r))).toList();
  if (todo.isEmpty) return fixed.length;

  String key((double, double) p) => '${p.$1.toStringAsFixed(4)},${p.$2.toStringAsFixed(4)}';
  // 이미 정해진 것들 (같은 사람 기록 전체에서)
  final hospByName = <String, PlaceHit>{};
  final pharmByHosp = <String, PlaceHit>{}; // "약국이름|병원위치"
  PlaceHit hitOf(String name, String addr, String code, (double, double) p) =>
      PlaceHit(name: name, addr: addr, code: code, lat: p.$1, lng: p.$2);
  for (final r in records) {
    final hn = hospitalNameOf(r);
    if (r.hospitalPos != null && hn.isNotEmpty) {
      hospByName[_n(hn)] ??= hitOf(hn, r.hospitalAddr, r.hospitalCode, r.hospitalPos!);
      if (r.pharmacyPos != null && r.pharmacy.isNotEmpty) {
        pharmByHosp['${_n(r.pharmacy)}|${key(r.hospitalPos!)}'] ??=
            hitOf(r.pharmacy, r.pharmacyAddr, r.pharmacyCode, r.pharmacyPos!);
      }
    }
  }

  // 1) 이름별 전국 후보 (같은 이름은 한 번만)
  final hNames = {for (final r in todo) if (needH(r)) hospitalNameOf(r)};
  final pNames = {for (final r in todo) if (needP(r)) r.pharmacy};
  final jobs = [for (final n in hNames) (n, false), for (final n in pNames) (n, true)];
  final cand = <(String, bool), List<PlaceHit>>{};
  var done = 0, total = jobs.length;
  for (var i = 0; i < jobs.length; i += 4) {
    final batch = jobs.skip(i).take(4).toList();
    final got = await Future.wait(batch.map((j) => sameName(api, j.$1, pharmacy: j.$2)));
    for (var k = 0; k < batch.length; k++) {
      cand[batch[k]] = got[k];
    }
    done += batch.length;
    onProgress?.call(done, total);
  }

  final changed = <MedRecord>{};
  void setH(MedRecord r, PlaceHit h) {
    if (r.hospital.isEmpty) r.hospital = hospitalNameOf(r);
    if (r.hospitalAddr.isEmpty) r.hospitalAddr = h.addr;
    r.hospitalCode = h.code;
    r.hospitalPos = posOf(h);
    hospByName[_n(r.hospital)] ??= h;
    changed.add(r);
  }

  void setP(MedRecord r, PlaceHit p) {
    if (r.pharmacyAddr.isEmpty) r.pharmacyAddr = p.addr;
    r.pharmacyCode = p.code;
    r.pharmacyPos = posOf(p);
    if (r.hospitalPos != null) pharmByHosp['${_n(r.pharmacy)}|${key(r.hospitalPos!)}'] ??= p;
    changed.add(r);
  }

  final nearCache = <String, List<PlaceHit>>{};
  Future<List<PlaceHit>> near(String name, (double, double) anchor, bool pharmacy,
      {double radius = kPairRadius}) async {
    final k = '${pharmacy ? 'p' : 'h'}|${_n(name)}|${key(anchor)}|${radius.round()}';
    final c = nearCache[k];
    if (c != null) return c;
    total++;
    final got = await sameNameNear(api, name, anchor, pharmacy: pharmacy, radius: radius);
    done++;
    onProgress?.call(done, total);
    return nearCache[k] = got;
  }

  // 한쪽이 정해지면 다른 쪽이 풀릴 수 있으므로 바뀌는 게 없을 때까지 (최대 3바퀴)
  for (var round = 0; round < 3; round++) {
    final before = changed.length;
    for (final r in todo) {
      final hn = hospitalNameOf(r);
      // 병원: 같은 이름이 이미 정해졌거나 전국에 한 곳뿐이면
      if (needH(r)) {
        final known = hospByName[_n(hn)];
        final c = cand[(hn, false)] ?? const [];
        if (known != null) {
          setH(r, known);
        } else if (c.length == 1) {
          setH(r, c.first);
        }
      }
      // 약국: 같은 병원 옆의 같은 이름이 이미 정해졌거나, 전국에 한 곳뿐이면
      if (needP(r)) {
        final known = r.hospitalPos == null
            ? null
            : pharmByHosp['${_n(r.pharmacy)}|${key(r.hospitalPos!)}'];
        final c = cand[(r.pharmacy, true)] ?? const [];
        if (known != null) {
          setP(r, known);
        } else if (c.length == 1) {
          setP(r, c.first);
        } else if (r.hospitalPos != null) {
          // 병원 주변 1km 안에 같은 이름 약국이 딱 한 곳이면 그곳
          final n = await near(r.pharmacy, r.hospitalPos!, true);
          if (n.length == 1) setP(r, n.first);
        }
      }
      // 약국만 정해졌으면: 약국 주변 1km 안에 같은 이름 병원이 딱 한 곳이면 그곳
      if (needH(r) && r.pharmacyPos != null) {
        final n = await near(hn, r.pharmacyPos!, false);
        if (n.length == 1) setH(r, n.first);
      }
      // 둘 다 흔한 이름이라 아무것도 못 정했으면: 같은 이름 병원마다 바로 옆(500m)에
      // 같은 이름 약국이 있는지 보고, 그런 짝이 전국에 딱 하나면 그 짝으로 확정
      if (round == 0 && needH(r) && needP(r)) {
        final hs = cand[(hn, false)] ?? const [];
        if (hs.length > 1 && hs.length <= kTwinMaxHosp) {
          final twins = <(PlaceHit, PlaceHit)>[];
          for (final h in hs) {
            final ps = await near(r.pharmacy, posOf(h)!, true, radius: kTwinRadius);
            for (final p in ps) {
              twins.add((h, p));
            }
            if (twins.length > 1) break; // 둘 이상이면 확정하지 않음
          }
          if (twins.length == 1) {
            setH(r, twins.first.$1);
            setP(r, twins.first.$2);
          }
        }
      }
    }
    if (changed.length == before) break;
  }
  return {...changed, ...fixed}.length;
}
