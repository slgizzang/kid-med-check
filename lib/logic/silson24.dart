/// 실손24(보험개발원) 참여기관 여부 확인.
/// 실손24 누리집의 '참여병원' 검색이 쓰는 요청과 같은 것을 이름 + 위치로 한 번 보낸다
/// (위치는 그 화면처럼 실손24가 내준 키로 AES-GCM 암호화해서 보냄).
/// 공식 공개 API가 아니므로 바뀌거나 막힐 수 있다 → 실패하면 '확인 불가'로 두고 앱은 그대로 동작한다.
/// 같은 기관은 7일 동안 다시 묻지 않는다 (휴대폰에 저장).
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'place_name.dart';

enum SilsonState { enabled, notEnabled, unknown }

/// 판정하지 못한 이유
enum SilsonMiss { none, noResponse, notFound, ambiguous }

class SilsonCheck {
  const SilsonCheck(this.state,
      {this.name = '', this.addr = '', this.lat, this.lng, this.miss = SilsonMiss.none});
  final SilsonState state;
  final SilsonMiss miss;

  /// 실손24에 등록된 기관 이름·주소·위치 (찾았을 때)
  final String name;
  final String addr;
  final double? lat;
  final double? lng;
}

class Silson24 {
  Silson24({http.Client? client}) : _client = client ?? http.Client(), _useCache = client == null;

  final http.Client _client;
  final bool _useCache;

  static const _url =
      'https://www.silson24.or.kr/cmm/api/v2/claim/getSearchHospitalsLocation';
  static const _keyUrl = 'https://www.silson24.or.kr/cmm/api/v1/base/genGcmAesKey';

  /// 실손24 화면과 같은 방식: base64(12바이트 nonce + AES-GCM 암호문·태그)
  static String encrypt(String plain, Uint8List key, {Uint8List? iv}) {
    final nonce = iv ??
        Uint8List.fromList(List.generate(12, (_) => math.Random.secure().nextInt(256)));
    final c = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final out = c.process(Uint8List.fromList(utf8.encode(plain)));
    return base64Encode([...nonce, ...out]);
  }

  static String decrypt(String enc, Uint8List key) {
    final raw = base64Decode(enc);
    final c = GCMBlockCipher(AESEngine())
      ..init(false,
          AEADParameters(KeyParameter(key), 128, raw.sublist(0, 12), Uint8List(0)));
    return utf8.decode(c.process(raw.sublist(12)));
  }
  static const _ttl = Duration(days: 7);
  static const _prefix = 'silson24:';
  static final _mem = <String, SilsonCheck>{};

  static String _n(String s) => s.replaceAll(RegExp(r'[\s()·.,\-]'), '');

  /// [name] 기관이 실손24로 서류 없이 청구 가능한지. [addr]를 알면 같은 이름이 여럿일 때 가려낸다.
  /// [near]: 주소를 모를 때 같은 이름 중 가까운 곳을 고를 기준점 (병원 위치 또는 내 위치).
  /// [code]: 심평원 요양기관 코드(있으면 가장 정확). [addr]: 도로명 주소(코드 다음으로 정확).
  /// [at]: 이 기관의 위치(알면). 실손24를 이 위치 기준 거리순으로 찾아, 같은 이름 중 바로 그 자리의 곳을 고른다.
  Future<SilsonCheck> check(String name,
      {required bool pharmacy,
      String addr = '',
      String code = '',
      (double, double)? at,
      (double, double)? near}) async {
    final q = searchablePlaceName(name);
    if (q.length < 2) return const SilsonCheck(SilsonState.unknown, miss: SilsonMiss.notFound);
    final center = at ?? near;
    final nearKey = center == null
        ? ''
        : '${at == null ? 'n' : 'a'}${center.$1.toStringAsFixed(3)},${center.$2.toStringAsFixed(3)}';
    final key = '${pharmacy ? 'p' : 'h'}|${_n(q)}|${_n(addr)}|$code|$nearKey';
    if (_useCache) {
      final m = _mem[key];
      if (m != null) return m;
      final d = await _read(key);
      if (d != null) return _mem[key] = d;
    }
    SilsonCheck r;
    try {
      // 1차: 정리한 이름으로, 못 찾으면 2차: 종별(의원·약국 등)을 뗀 이름으로 (실손24는 부분 검색)
      r = pick(await _search(q, pharmacy: pharmacy, center: center), q, addr,
          code: code, at: at, near: near);
      final b = _base(q);
      if (r.miss == SilsonMiss.notFound && b.length >= 2 && b != _n(q)) {
        r = pick(await _search(b, pharmacy: pharmacy, center: center), q, addr,
            code: code, at: at, near: near);
      }
    } catch (_) {
      return const SilsonCheck(SilsonState.unknown, miss: SilsonMiss.noResponse);
    }
    if (_useCache && r.state != SilsonState.unknown) {
      _mem[key] = r;
      await _write(key, r);
    }
    return r;
  }

  static const _headers = {'Content-Type': 'application/json', 'Accept': 'application/json'};

  /// 위치를 암호화할 키 (실손24가 요청마다 내줌)
  Future<(String, Uint8List)?> _gcmKey() async {
    try {
      final resp = await _client
          .post(Uri.parse(_keyUrl), headers: _headers, body: '{}')
          .timeout(const Duration(seconds: 10));
      final d = jsonDecode(utf8.decode(resp.bodyBytes));
      final r = d is Map ? d['result'] : null;
      if (r is! Map) return null;
      return ('${r['encUuid']}', base64Decode('${r['key']}'));
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _search(String q,
      {required bool pharmacy, (double, double)? center}) async {
    final body = <String, dynamic>{
      'keyword': q,
      'servicedOnly': false,
      'hospitalType': pharmacy ? 'pharmacy' : 'hospital',
      'hospitalAsortCds': [],
      'zoom': 16,
      'offset': {'offset': 0, 'limit': 100},
      'isCurrentLocation': false,
      'deptCd': '',
      'orderBy': 'distance',
    };
    if (center != null) {
      // 위치를 주면 그 자리에서 가까운 순으로 돌려준다 (이름이 같은 곳이 많아도 근처가 앞에 옴)
      final k = await _gcmKey();
      if (k != null) {
        body['encLat'] = encrypt(center.$1.toStringAsFixed(7), k.$2);
        body['encLng'] = encrypt(center.$2.toStringAsFixed(7), k.$2);
        body['encUuid'] = k.$1;
      }
    }
    final resp = await _client
        .post(Uri.parse(_url), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    final d = jsonDecode(utf8.decode(resp.bodyBytes));
    final list = d is Map ? d['result'] : null;
    if (list is! List) return const [];
    return [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)];
  }

  /// 이름 비교용: 공백·기호를 떼고, 끝의 종별(의원·병원·약국 등)도 뗀 값
  static String _base(String s) =>
      _n(s).replaceFirst(RegExp(r'(의원|병원|약국|치과의원|한의원|의료원|센터|클리닉)$'), '');

  static double _dist(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  static double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  /// 검색 결과에서 이 기관을 고른다.
  /// 1) 이름: 정확히 같은 곳 → 없으면 종별(의원·약국 등)만 다른 곳 ("1층온누리약국"처럼 다른 말이 붙은 곳은 다른 기관으로 봄)
  /// 2) 여럿이면: 주소가 겹치는 곳 → 기준점([near])에서 확실히 가장 가까운 곳
  /// 3) 그래도 여럿이면 모두 같은 상태일 때만 판정
  /// 도로명 주소 비교용 열쇠: "서울특별시 송파구 올림픽로43길 88, 서울아산병원 (풍납동)" → "서울특별시송파구올림픽로43길88"
  static String addrKey(String a) => a
      .replaceAll(RegExp(r'\([^)]*\)'), '')
      .split(',')
      .first
      .replaceAll(RegExp(r'\s'), '')
      .trim();

  static SilsonCheck pick(List<Map<String, dynamic>> items, String query, String addr,
      {String code = '', (double, double)? at, (double, double)? near}) {
    String nm(Map<String, dynamic> e) => '${e['insttNm'] ?? ''}';
    SilsonCheck of(Map<String, dynamic> e) => SilsonCheck(
          e['serviceEnabled'] == true ? SilsonState.enabled : SilsonState.notEnabled,
          name: nm(e),
          addr: '${e['rnAddr'] ?? ''}',
          lat: _num(e['lat']),
          lng: _num(e['lng']),
        );
    // 0) 코드가 같으면 확실히 같은 곳 (미연계 기관은 실손24도 심평원 코드를 씀)
    if (code.isNotEmpty) {
      for (final e in items) {
        if ('${e['hospitalCd'] ?? ''}' == code) return of(e);
      }
    }
    // 0-2) 도로명 주소가 같으면 같은 곳 (이름 표기가 달라도 됨)
    final ak = addrKey(addr);
    if (ak.length >= 8) {
      final same = items.where((e) => addrKey('${e['rnAddr'] ?? ''}') == ak).toList();
      // 같은 건물에 병원이 여럿일 수 있으니 이름도 비슷한 곳을 먼저
      final qb = _base(query);
      final named = same.where((e) {
        final b = _base(nm(e));
        return b.contains(qb) || qb.contains(b);
      }).toList();
      if (named.length == 1) return of(named.first);
      if (same.length == 1) return of(same.first);
    }
    final qn = _n(query), qb = _base(query);
    var cands = items.where((e) => _n(nm(e)) == qn).toList();
    if (cands.isEmpty && qb.length >= 2) {
      cands = items.where((e) => _base(nm(e)) == qb).toList();
    }
    if (cands.isEmpty) return const SilsonCheck(SilsonState.unknown, miss: SilsonMiss.notFound);

    double dist(Map<String, dynamic> e, (double, double) p) {
      final la = _num(e['lat']), lo = _num(e['lng']);
      return la == null || lo == null ? double.infinity : _dist(p.$1, p.$2, la, lo);
    }
    // 이 기관의 위치를 알면: 같은 이름 중 바로 그 자리(300m 안)에 있는 곳
    if (at != null) {
      final here = cands.where((e) => dist(e, at) < 300).toList()
        ..sort((a, b) => dist(a, at).compareTo(dist(b, at)));
      if (here.isNotEmpty) return of(here.first);
    }

    if (cands.length > 1 && addr.trim().isNotEmpty) {
      // 시·구·도로명까지 겹치는 곳
      final words = addr.split(RegExp(r'\s+')).where((w) => w.length >= 2).take(4).toList();
      int score(Map<String, dynamic> e) {
        final a = '${e['rnAddr'] ?? ''}';
        return words.where((w) => a.contains(w)).length;
      }
      cands.sort((a, b) => score(b).compareTo(score(a)));
      final best = score(cands.first);
      if (best >= 2) cands = cands.where((e) => score(e) == best).toList();
    }
    if (cands.length > 1 && near != null) {
      // 기준점에서 가장 가까운 곳이 5km 안이고, 두 번째보다 확실히(2배 이상) 가까우면 그곳
      double d(Map<String, dynamic> e) => dist(e, near);
      cands.sort((a, b) => d(a).compareTo(d(b)));
      final d0 = d(cands.first), d1 = d(cands[1]);
      if (d0 < 5000 && (d1 == double.infinity || d1 >= d0 * 2)) cands = [cands.first];
    }
    final states = cands.map((e) => e['serviceEnabled'] == true).toSet();
    if (states.length != 1) {
      return const SilsonCheck(SilsonState.unknown, miss: SilsonMiss.ambiguous);
    }
    final e = cands.first;
    final one = cands.length == 1;
    return SilsonCheck(
      states.first ? SilsonState.enabled : SilsonState.notEnabled,
      name: nm(e),
      addr: one ? '${e['rnAddr'] ?? ''}' : '',
      lat: one ? _num(e['lat']) : null,
      lng: one ? _num(e['lng']) : null,
    );
  }

  static Future<SilsonCheck?> _read(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('$_prefix$key');
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map;
      final t = DateTime.fromMillisecondsSinceEpoch(j['t'] as int);
      if (DateTime.now().difference(t) > _ttl) return null;
      return SilsonCheck(SilsonState.values.byName('${j['s']}'),
          name: '${j['n'] ?? ''}',
          addr: '${j['a'] ?? ''}',
          lat: (j['la'] as num?)?.toDouble(),
          lng: (j['lo'] as num?)?.toDouble());
    } catch (_) {
      return null;
    }
  }

  static Future<void> _write(String key, SilsonCheck c) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          '$_prefix$key',
          jsonEncode({
            't': DateTime.now().millisecondsSinceEpoch,
            's': c.state.name,
            'n': c.name,
            'a': c.addr,
            if (c.lat != null) 'la': c.lat,
            if (c.lng != null) 'lo': c.lng,
          }));
    } catch (_) {}
  }
}
