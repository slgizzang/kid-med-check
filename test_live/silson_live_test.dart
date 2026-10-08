// 실제 심평원·실손24 자료로 연계 판정을 점검 (수동 실행, 네트워크 필요)
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kid_med_check/logic/dur_api.dart';
import 'package:kid_med_check/logic/place_name.dart';
import 'package:kid_med_check/logic/models.dart';
import 'package:kid_med_check/logic/place_resolver.dart';
import 'package:kid_med_check/logic/silson24.dart';

double dist((double, double) a, double? la, double? lo) {
  if (la == null || lo == null) return -1;
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(la - a.$1), dLon = rad(lo - a.$2);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(a.$1)) * math.cos(rad(la)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.asin(math.sqrt(h));
}

void main() {
  test('live', () async {
    final key = Platform.environment['DUR_API_KEY'] ?? '';
    final client = http.Client();
    final api = DurApi(key, client: client);
    final s24 = Silson24(client: client);
    const misa = (37.5636, 127.1906); // 하남 미사
    const gangdong = (37.5301, 127.1238); // 강동구청 근처
    var ok = 0, fail = 0;
    for (final center in [misa, gangdong]) {
      for (final pharmacy in [false, true]) {
        final places = await api.searchPlaces('', pharmacy: pharmacy, lat: center.$1, lon: center.$2, radius: 1500);
        for (final p in places.take(25)) {
          final at = p.lat != null && p.lng != null ? (p.lat!, p.lng!) : null;
          final c = await s24.check(p.name, pharmacy: pharmacy, addr: p.addr, code: p.code, at: at);
          if (c.state != SilsonState.unknown) {
            ok++;
            print('OK  ${pharmacy ? "P" : "H"} ${p.name} -> ${c.state.name} (${c.name})');
            continue;
          }
          fail++;
          print('FAIL ${pharmacy ? "P" : "H"} ${p.name} | q=${searchablePlaceName(p.name)} | miss=${c.miss.name} | addr=${p.addr} | at=$at | code=${p.code.length > 10 ? p.code.substring(0, 10) : p.code}');
          final raw = await s24.rawSearch(searchablePlaceName(p.name), pharmacy: pharmacy, center: at);
          print('     s24 results=${raw.length}');
          for (final e in raw.take(6)) {
            final la = e['lat'] is num ? (e['lat'] as num).toDouble() : double.tryParse('${e['lat']}');
            final lo = e['lng'] is num ? (e['lng'] as num).toDouble() : double.tryParse('${e['lng']}');
            print('     - ${e['insttNm']} | ${e['rnAddr']} | svc=${e['serviceEnabled']} | cd=${'${e['hospitalCd']}'.length > 10 ? '${e['hospitalCd']}'.substring(0, 10) : e['hospitalCd']} | d=${at == null ? -1 : dist(at, la, lo).round()}m');
          }
        }
      }
    }
    print('SUMMARY ok=$ok fail=$fail');
  }, timeout: const Timeout(Duration(minutes: 8)));

  // 심평원에서 불러온 기록처럼 이름만 있을 때 (위치 권한 없음): 병원 + 그 옆 약국 → fillPlaces → 실손24
  test('imported', () async {
    final key = Platform.environment['DUR_API_KEY'] ?? '';
    final client = http.Client();
    final api = DurApi(key, client: client);
    final s24 = Silson24(client: client);
    final recs = <MedRecord>[];
    final truth = <MedRecord, (String, String)>{};
    for (final center in [(37.5636, 127.1906), (37.5301, 127.1238), (37.4979, 127.0276)]) {
      final hosps = await api.searchPlaces('', pharmacy: false, lat: center.$1, lon: center.$2, radius: 1500);
      for (final h in hosps.take(15)) {
        final hp = posOf(h);
        if (hp == null) continue;
        final near = await api.searchPlaces('', pharmacy: true, lat: hp.$1, lon: hp.$2, radius: 300);
        if (near.isEmpty) continue;
        final r = MedRecord(id: '${recs.length}', childId: 'c', title: 'x', createdAt: DateTime(2026),
            hospital: h.name, pharmacy: near.first.name);
        recs.add(r);
        truth[r] = (h.code, near.first.code);
      }
    }
    final changed = await fillPlaces(api, recs);
    var hRight = 0, pRight = 0, hKnown = 0, pKnown = 0;
    for (final r in recs) {
      final (hc, pc) = truth[r]!;
      if (r.hospitalCode == hc) hRight++; else print('HPOS ${r.hospital} -> ${r.hospitalCode.isEmpty ? "못 찾음" : "다른 곳 ${r.hospitalAddr}"}');
      if (r.pharmacyCode == pc) pRight++; else print('PPOS ${r.pharmacy} -> ${r.pharmacyCode.isEmpty ? "못 찾음" : "다른 곳 ${r.pharmacyAddr}"}');
      final ch = await s24.check(r.hospital, pharmacy: false,
          addr: r.hospitalAddr, code: r.hospitalCode, at: r.hospitalPos);
      final cp = await s24.check(r.pharmacy, pharmacy: true,
          addr: r.pharmacyAddr, code: r.pharmacyCode, at: r.pharmacyPos, near: r.hospitalPos);
      if (ch.state != SilsonState.unknown) hKnown++; else print('HFAIL ${r.hospital} miss=${ch.miss.name}');
      if (cp.state != SilsonState.unknown) pKnown++; else print('PFAIL ${r.pharmacy} miss=${cp.miss.name}');
    }
    print('SUMMARY2 records=${recs.length} changed=$changed hosp_pos_right=$hRight pharm_pos_right=$pRight s24_hosp_known=$hKnown s24_pharm_known=$pKnown');
  }, timeout: const Timeout(Duration(minutes: 12)));

  test('one', () async {
    final key = Platform.environment['DUR_API_KEY'] ?? '';
    final client = http.Client();
    final api = DurApi(key, client: client);
    final s24 = Silson24(client: client);
    for (final (name, ph) in [('명소아청소년과의원', false), ('메디파워약국', true)]) {
      final hs = await api.searchPlaces(name, pharmacy: ph, rows: 100);
      print('ONE HIRA $name -> ${hs.length}');
      for (final h in hs.where((h) => h.name.replaceAll(' ', '') == name).take(8)) {
        print('ONE   ${h.name} | ${h.addr} | ${h.lat},${h.lng} | ${h.code.substring(0, 10)}');
      }
      final m = hs.where((h) => h.addr.contains('뚝섬로 552')).toList();
      if (m.isEmpty) continue;
      final h = m.first;
      final at = (h.lat!, h.lng!);
      final c = await s24.check(h.name, pharmacy: ph, addr: h.addr, code: h.code, at: at);
      print('ONE CHECK ${h.name} -> ${c.state.name} miss=${c.miss.name} (${c.name} ${c.addr})');
      final raw = await s24.rawSearch(searchablePlaceName(h.name).replaceAll(' ', ''), pharmacy: ph, center: at);
      print('ONE S24 results=${raw.length}');
      for (final e in raw.take(10)) {
        print('ONE   - ${e['insttNm']} | ${e['rnAddr']} | ${e['detailAddr']} | svc=${e['serviceEnabled']} | ${e['lat']},${e['lng']} | cd=${'${e['hospitalCd']}'.length > 10 ? '${e['hospitalCd']}'.substring(0, 10) : e['hospitalCd']}');
      }
      print('ONE addrKey hira=${Silson24.addrKey(h.addr)}');
      for (final kw in ['', '소아']) {
        final around = await s24.rawSearch(kw, pharmacy: ph, center: at);
        print('ONE AROUND kw="$kw" results=${around.length}');
        for (final e in around.take(8)) {
          final la = double.tryParse('${e['lat']}'), lo = double.tryParse('${e['lng']}');
          print('ONE   ~ ${e['insttNm']} | ${e['rnAddr']} | svc=${e['serviceEnabled']} | d=${dist(at, la, lo).round()}m');
        }
      }
    }
  });
}
