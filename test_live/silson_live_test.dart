// 실제 심평원·실손24 자료로 연계 판정을 점검 (수동 실행, 네트워크 필요)
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kid_med_check/logic/dur_api.dart';
import 'package:kid_med_check/logic/place_name.dart';
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
}
