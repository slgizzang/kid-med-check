/// 실손24(보험개발원) 참여기관 여부 확인.
/// 실손24 누리집의 '참여병원' 검색이 쓰는 요청과 같은 것을 이름으로 한 번 보낸다.
/// 공식 공개 API가 아니므로 바뀌거나 막힐 수 있다 → 실패하면 '확인 불가'로 두고 앱은 그대로 동작한다.
/// 같은 기관은 7일 동안 다시 묻지 않는다 (휴대폰에 저장).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'place_name.dart';

enum SilsonState { enabled, notEnabled, unknown }

class SilsonCheck {
  const SilsonCheck(this.state, {this.name = '', this.addr = ''});
  final SilsonState state;

  /// 실손24에 등록된 기관 이름·주소 (찾았을 때)
  final String name;
  final String addr;
}

class Silson24 {
  Silson24({http.Client? client}) : _client = client ?? http.Client(), _useCache = client == null;

  final http.Client _client;
  final bool _useCache;

  static const _url =
      'https://www.silson24.or.kr/cmm/api/v2/claim/getSearchHospitalsLocation';
  static const _ttl = Duration(days: 7);
  static const _prefix = 'silson24:';
  static final _mem = <String, SilsonCheck>{};

  static String _n(String s) => s.replaceAll(RegExp(r'[\s()·.,\-]'), '');

  /// [name] 기관이 실손24로 서류 없이 청구 가능한지. [addr]를 알면 같은 이름이 여럿일 때 가려낸다.
  Future<SilsonCheck> check(String name, {required bool pharmacy, String addr = ''}) async {
    final q = searchablePlaceName(name);
    if (q.length < 2) return const SilsonCheck(SilsonState.unknown);
    final key = '${pharmacy ? 'p' : 'h'}|${_n(q)}|${_n(addr)}';
    if (_useCache) {
      final m = _mem[key];
      if (m != null) return m;
      final d = await _read(key);
      if (d != null) return _mem[key] = d;
    }
    final List<Map<String, dynamic>> items;
    try {
      items = await _search(q, pharmacy: pharmacy);
    } catch (_) {
      return const SilsonCheck(SilsonState.unknown);
    }
    final r = pick(items, q, addr);
    if (_useCache && r.state != SilsonState.unknown) {
      _mem[key] = r;
      await _write(key, r);
    }
    return r;
  }

  Future<List<Map<String, dynamic>>> _search(String q, {required bool pharmacy}) async {
    final resp = await _client
        .post(Uri.parse(_url),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'keyword': q,
              'servicedOnly': false,
              'hospitalType': pharmacy ? 'pharmacy' : 'hospital',
              'offset': {'offset': 0, 'limit': 50},
              'isCurrentLocation': false,
              'orderBy': 'distance',
            }))
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    final d = jsonDecode(utf8.decode(resp.bodyBytes));
    final list = d is Map ? d['result'] : null;
    if (list is! List) return const [];
    return [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)];
  }

  /// 검색 결과에서 이 기관을 고른다.
  /// 이름이 정확히 같은 곳 → 주소로 가리기 → 그래도 여럿이면 모두 같은 상태일 때만 판정.
  static SilsonCheck pick(List<Map<String, dynamic>> items, String query, String addr) {
    final qn = _n(query);
    var cands = items.where((e) => _n('${e['insttNm'] ?? ''}') == qn).toList();
    if (cands.isEmpty) return const SilsonCheck(SilsonState.unknown);
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
    final states = cands.map((e) => e['serviceEnabled'] == true).toSet();
    if (states.length != 1) return const SilsonCheck(SilsonState.unknown);
    final e = cands.first;
    return SilsonCheck(
      states.first ? SilsonState.enabled : SilsonState.notEnabled,
      name: '${e['insttNm'] ?? ''}',
      addr: '${e['rnAddr'] ?? ''}',
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
          name: '${j['n'] ?? ''}', addr: '${j['a'] ?? ''}');
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
          }));
    } catch (_) {}
  }
}
