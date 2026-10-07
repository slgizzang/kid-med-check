// 실제 심평원·실손24 자료로 연계 판정을 점검 (수동 실행, 네트워크 필요)
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kid_med_check/logic/dur_api.dart';
import 'package:kid_med_check/logic/place_name.dart';
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

  // 심평원에서 불러온 기록처럼 이름만 있을 때 (위치 권한 없음): 병원 + 그 옆 약국
  test('imported', () async {
    final key = Platform.environment['DUR_API_KEY'] ?? '';
    final client = http.Client();
    final api = DurApi(key, client: client);
    final s24 = Silson24(client: client);
    var pairOk = 0, pairFail = 0, hOk = 0, pOk = 0, n = 0;
    for (final center in [(37.5636, 127.1906), (37.5301, 127.1238), (37.4979, 127.0276)]) {
      final hosps = await api.searchPlaces('', pharmacy: false, lat: center.$1, lon: center.$2, radius: 1500);
      for (final h in hosps.take(15)) {
        final hp = posOf(h);
        if (hp == null) continue;
        final near = await api.searchPlaces('', pharmacy: true, lat: hp.$1, lon: hp.$2, radius: 300);
        if (near.isEmpty) continue;
        final p = near.first; // 병원에서 가장 가까운 약국
        n++;
        final hs = await sameName(api, h.name, pharmacy: false);
        final ps = await sameName(api, p.name, pharmacy: true);
        final pair = resolvePair(hosps: hs, pharms: ps);
        final hRight = pair.hospital?.code == h.code;
        final pRight = pair.pharmacy?.code == p.code;
        if (hRight && pRight) {
          pairOk++;
        } else {
          pairFail++;
          print('PAIRFAIL ${h.name}(${hs.length}곳) + ${p.name}(${ps.length}곳) -> h=${pair.hospital?.addr} p=${pair.pharmacy?.addr}');
        }
        final ch = await s24.check(h.name, pharmacy: false,
            addr: pair.hospital?.addr ?? '', code: pair.hospital?.code ?? '',
            at: pair.hospital == null ? null : posOf(pair.hospital!));
        final cp = await s24.check(p.name, pharmacy: true,
            addr: pair.pharmacy?.addr ?? '', code: pair.pharmacy?.code ?? '',
            at: pair.pharmacy == null ? null : posOf(pair.pharmacy!),
            near: pair.hospital == null ? null : posOf(pair.hospital!));
        if (ch.state != SilsonState.unknown) hOk++; else print('HFAIL ${h.name} miss=${ch.miss.name} addr=${pair.hospital?.addr}');
        if (cp.state != SilsonState.unknown) pOk++; else print('PFAIL ${p.name} miss=${cp.miss.name} addr=${pair.pharmacy?.addr}');
      }
    }
    print('SUMMARY2 records=$n pair_ok=$pairOk pair_fail=$pairFail hospital_known=$hOk pharmacy_known=$pOk');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
