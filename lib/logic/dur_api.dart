import 'dart:convert';

import 'package:http/http.dart' as http;

import 'age_rule.dart';

/// 식품의약품안전처 DUR 품목정보 - 특정연령대금기 정보조회
/// https://www.data.go.kr/data/15059486/openapi.do
class DurApi {
  DurApi(String serviceKey, {http.Client? client})
      : _key = _normalizeKey(serviceKey),
        _client = client ?? http.Client();

  final String _key;
  final http.Client _client;

  static const _host = 'apis.data.go.kr';
  static const _path =
      '/1471000/DURPrdlstInfoService03/getSpcifyAgrdeTabooInfoList03';

  /// 사용자가 "Encoding" 키(%2B 등 포함)를 붙여넣어도 동작하도록 한 번 디코딩한다.
  static String _normalizeKey(String key) {
    final k = key.trim();
    if (k.contains('%')) {
      try {
        return Uri.decodeComponent(k);
      } catch (_) {
        return k;
      }
    }
    return k;
  }

  Future<List<TabooRow>> searchAgeTaboo(String itemName) async {
    final uri = Uri.https(_host, _path, {
      'serviceKey': _key,
      'type': 'json',
      'pageNo': '1',
      'numOfRows': '100',
      'itemName': itemName,
    });

    final http.Response resp;
    try {
      resp = await _client.get(uri).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw DurApiException('네트워크 연결을 확인해주세요. ($e)');
    }

    final body = utf8.decode(resp.bodyBytes, allowMalformed: true).trim();

    // 인증키 오류 등은 type=json이어도 XML로 오는 경우가 있다.
    if (body.startsWith('<')) {
      final code = RegExp(r'<returnReasonCode>(.*?)</returnReasonCode>')
              .firstMatch(body)
              ?.group(1) ??
          RegExp(r'<resultCode>(.*?)</resultCode>').firstMatch(body)?.group(1);
      final msg = RegExp(r'<returnAuthMsg>(.*?)</returnAuthMsg>')
              .firstMatch(body)
              ?.group(1) ??
          RegExp(r'<resultMsg>(.*?)</resultMsg>').firstMatch(body)?.group(1) ??
          'HTTP ${resp.statusCode}';
      throw DurApiException(_friendly(msg, code));
    }
    if (resp.statusCode != 200) {
      throw DurApiException(_friendly(body, '${resp.statusCode}'));
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw DurApiException('응답을 해석하지 못했어요: ${_short(body)}');
    }
    if (decoded is! Map) throw DurApiException('예상치 못한 응답 형식');

    final root = (decoded['response'] is Map) ? decoded['response'] as Map : decoded;
    final header = root['header'];
    if (header is Map) {
      final code = '${header['resultCode'] ?? '00'}';
      if (code != '00') {
        throw DurApiException(
            _friendly('${header['resultMsg'] ?? ''}', code));
      }
    }
    final bodyMap = root['body'];
    if (bodyMap is! Map) return [];
    return _items(bodyMap['items']).map(TabooRow.fromJson).toList();
  }

  static List<Map<String, dynamic>> _items(dynamic items) {
    final out = <Map<String, dynamic>>[];
    void add(dynamic v) {
      if (v is Map) {
        if (v['item'] != null) {
          add(v['item']);
        } else {
          out.add(v.map((k, val) => MapEntry('$k', val)));
        }
      } else if (v is List) {
        for (final e in v) {
          add(e);
        }
      }
    }

    add(items);
    return out;
  }

  static String _short(String s) => s.length > 120 ? '${s.substring(0, 120)}…' : s;

  static String _friendly(String msg, String? code) {
    final m = '$msg ${code ?? ''}';
    if (m.contains('SERVICE_KEY') || code == '30' || code == '31') {
      return '인증키가 등록되지 않았어요. 활용신청 승인 직후라면 1~2시간 뒤 다시 시도하고, '
          '"일반 인증키(Decoding)"를 넣었는지 확인해주세요.';
    }
    if (m.contains('LIMITED_NUMBER_OF_SERVICE_REQUESTS') || code == '22') {
      return '오늘 조회 가능 횟수를 초과했어요. 내일 다시 시도해주세요.';
    }
    if (m.contains('NO_OPENAPI_SERVICE') || code == '12') {
      return 'API 서비스를 찾을 수 없어요. 활용신청한 서비스가 맞는지 확인해주세요.';
    }
    if (m.contains('UNREGISTERED_IP') || code == '32') {
      return '등록되지 않은 IP로 호출했어요.';
    }
    return '조회 실패: ${_short(msg)} ${code ?? ''}'.trim();
  }
}

class DurApiException implements Exception {
  DurApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// API 한 줄(품목×성분)
class TabooRow {
  TabooRow({
    required this.itemName,
    required this.company,
    required this.ingredient,
    required this.content,
    required this.remark,
    required this.date,
    required this.rule,
  });

  final String itemName;
  final String company;
  final String ingredient;
  final String content;
  final String remark;
  final String date;
  final AgeRule rule;

  static String _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && '$v'.trim().isNotEmpty && '$v' != 'null') {
        return '$v'.trim();
      }
    }
    return '';
  }

  factory TabooRow.fromJson(Map<String, dynamic> m) {
    final content = _pick(m, [
      'PROHBT_CONTENT',
      'SPCIFY_AGRDE_TABOO_CN',
      'TABOO_CONTENT',
      'CONTENT',
    ]);
    final remark = _pick(m, ['REMARK', 'SPCIFY_AGRDE_TABOO_REMARK']);
    var ruleText = '$content $remark';
    if (content.isEmpty) {
      // 필드명이 바뀌어도 연령 문구를 놓치지 않도록 모든 문자열 값을 본다.
      ruleText = m.entries
          .where((e) => e.key != 'ITEM_NAME' && e.key != 'ENTP_NAME')
          .map((e) => '${e.value}')
          .join(' ');
    }
    return TabooRow(
      itemName: _pick(m, ['ITEM_NAME', 'itemName']),
      company: _pick(m, ['ENTP_NAME', 'entpName']),
      ingredient: _pick(m, ['INGR_KOR_NAME', 'INGR_NAME', 'MAIN_INGR', 'MIX_INGR']),
      content: content,
      remark: remark,
      date: _pick(m, ['NOTIFICATION_DATE', 'CHANGE_DATE']),
      rule: AgeRule.parse(ruleText),
    );
  }
}
