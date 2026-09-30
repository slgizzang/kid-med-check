import 'dart:convert';

import 'package:http/http.dart' as http;

import 'age_rule.dart';
import 'drug_name_extractor.dart';
import 'similarity.dart';

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

  /// e약은요(의약품개요정보): 쉬운 말로 된 효능·사용법
  static const _easyPath = '/1471000/DrbEasyDrugInfoService/getDrbEasyDrugList';

  /// DUR 품목정보: 약 분류(예: 해열진통소염제)·성분
  static const _durItemPath = '/1471000/DURPrdlstInfoService03/getDurPrdlstInfoList03';

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
    final items = await _fetchItems(_path, {'itemName': itemName}, 100);
    return items.map(TabooRow.fromJson).toList();
  }

  /// 약 설명. e약은요에서 먼저 찾고, 없으면 DUR 품목정보의 분류로 대신한다.
  /// 설명은 부가 정보라 실패해도 예외를 던지지 않고 null을 준다.
  Future<DrugInfo?> searchDrugInfo(String itemName) async {
    try {
      final easy = await _fetchItems(_easyPath, {'itemName': itemName}, 5);
      if (easy.isNotEmpty) return DrugInfo.fromEasy(easy.first);
    } catch (_) {}
    try {
      final dur = await _fetchItems(_durItemPath, {'itemName': itemName}, 5);
      if (dur.isNotEmpty) return DrugInfo.fromDur(dur.first);
    } catch (_) {}
    return null;
  }

  /// 이름 일부로 제품 목록을 찾는다 (DUR 품목정보 + e약은요). 실패해도 빈 목록.
  Future<List<ProductHit>> searchProducts(String q) async {
    final byName = <String, ProductHit>{};
    try {
      for (final m in await _fetchItems(_durItemPath, {'itemName': q}, 40)) {
        final h = ProductHit.fromDur(m);
        if (h.fullName.isNotEmpty) byName.putIfAbsent(h.displayName, () => h);
      }
    } catch (_) {}
    try {
      for (final m in await _fetchItems(_easyPath, {'itemName': q}, 20)) {
        final h = ProductHit.fromEasy(m);
        if (h.fullName.isEmpty) continue;
        final old = byName[h.displayName];
        byName[h.displayName] = old == null ? h : old.withEasy(m);
      }
    } catch (_) {}
    return byName.values.toList();
  }

  /// 입력한 이름과 가장 비슷한 제품 1개와, 비슷한 후보들을 고른다. 오타도 어느 정도 허용.
  Future<Resolution> resolve(String query) async {
    final q = DrugNameExtractor.toSearchName(query);
    final hits = <String, ProductHit>{};
    void addAll(List<ProductHit> list) {
      for (final h in list) {
        hits.putIfAbsent(h.displayName, () => h);
      }
    }

    addAll(await searchProducts(q));
    // 연령금기 목록에 있는 제품도 후보로 (품목정보 검색에 안 나오는 경우 대비)
    final tabooNames = <String>{};
    final tabooRows = <String, List<TabooRow>>{};
    try {
      for (final r in await searchAgeTaboo(q)) {
        final h = ProductHit(
            fullName: r.itemName, company: r.company, ingredient: r.ingredient);
        tabooNames.add(h.displayName);
        tabooRows.putIfAbsent(h.displayName, () => []).add(r);
        hits.putIfAbsent(h.displayName, () => h);
      }
    } catch (_) {}
    final hasPrefixMatch = hits.values.any((h) => h.searchName.startsWith(q));
    if (!hasPrefixMatch) {
      // 오타·제형 차이 대비: 제형 뗀 이름, 앞 두 글자로도 찾아본다.
      final extra = <String>[
        ...DrugNameExtractor.searchVariants(q).skip(1),
        if (q.length >= 3) q.substring(0, 2),
      ];
      for (final v in extra) {
        addAll(await searchProducts(v));
      }
    }

    final ranked = hits.values.toList()
      ..sort((a, b) => nameScore(q, a.searchName).compareTo(nameScore(q, b.searchName)));
    // "정확히 찾았다"고 할 수 있는 건 이름 앞부분이 거의 같을 때만 (오타 1~2자 허용).
    // 가까운 후보가 딱 하나이거나, 입력이 제품명과 정확히 같을 때만 "찾았다"고 한다.
    // (예: "코대원" → 코대원정·코대원포르테시럽… 여러 개라 고르게 함)
    final close = ranked.where((h) => nameScore(q, h.searchName) <= 3).toList();
    final exact = close.where((h) => h.searchName == q).toList();
    ProductHit? best;
    var ambiguous = false;
    if (exact.isNotEmpty) {
      best = exact.first;
    } else if (close.length == 1) {
      best = close.first;
    } else if (close.length > 1) {
      ambiguous = true;
    }
    final similar = ranked
        .where((h) => h != best && nameScore(q, h.searchName) <= 8)
        .take(ambiguous ? 10 : 6)
        .toList();
    return Resolution(best, similar, tabooNames, ambiguous, tabooRows);
  }

  static const _pwnmPath = '/1471000/DURPrdlstInfoService03/getPwnmTabooInfoList03';
  static const _usjntPath = '/1471000/DURPrdlstInfoService03/getUsjntTabooInfoList03';

  /// 해당 제품 이름으로 조회한 행 중 그 제품의 것만
  Future<List<Map<String, dynamic>>> _itemRows(String path, ProductHit best,
      {int pages = 1}) async {
    final all = <Map<String, dynamic>>[];
    for (var page = 1; page <= pages; page++) {
      final items = await _fetchItems(
          path, {'itemName': best.searchName, 'pageNo': '$page'}, 100);
      all.addAll(items);
      if (items.length < 100) break;
    }
    String name(Map m) => '${m['ITEM_NAME'] ?? ''}';
    final exact = all
        .where((m) => ProductHit(fullName: name(m)).displayName == best.displayName)
        .toList();
    return exact.isNotEmpty
        ? exact
        : all.where((m) => name(m).startsWith(best.searchName)).toList();
  }

  /// DUR 임부금기
  Future<List<SimpleTaboo>> pregnancyTaboo(ProductHit best) async {
    try {
      final rows = await _itemRows(_pwnmPath, best);
      return rows
          .map((m) => SimpleTaboo(
                ingredient: TabooRow._pick(m, ['INGR_NAME', 'INGR_KOR_NAME']),
                content: TabooRow._pick(m, ['PROHBT_CONTENT', 'REMARK']),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 이름 일부로 찾은 임부금기 제품명들 (후보 목록 표시용)
  Future<Set<String>> pregnancyNames(String q) async {
    try {
      final items = await _fetchItems(_pwnmPath, {'itemName': q}, 100);
      return {
        for (final m in items) ProductHit(fullName: '${m['ITEM_NAME'] ?? ''}').displayName
      };
    } catch (_) {
      return {};
    }
  }

  /// DUR 병용금기: 이 제품과 함께 쓰면 안 되는 상대 약(제품명·성분)
  Future<List<MixTaboo>> mixTaboo(ProductHit best) async {
    try {
      final rows = await _itemRows(_usjntPath, best, pages: 2);
      return rows
          .map((m) => MixTaboo(
                partnerItem: TabooRow._pick(m, ['MIXTURE_ITEM_NAME', 'MIX_ITEM_NAME']),
                partnerIngr: TabooRow._pick(m, [
                  'MIXTURE_INGR_KOR_NAME',
                  'MIXTURE_INGR_NAME',
                  'MIX_INGR_KOR_NAME',
                ]),
                reason: TabooRow._pick(m, ['PROHBT_CONTENT', 'REMARK']),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// DUR 성분정보: 성분 단위 병용금기 표 (성분 A + 성분 B = 금기)
  static const _ingrMixPath = '/1471000/DURIrdntInfoService03/getUsjntTabooInfoList02';
  static Future<List<MixPair>>? _mixTable;

  Future<List<MixPair>> _loadMixTable() async {
    final out = <MixPair>[];
    var pageSize = 0;
    for (var page = 1; page <= 60; page++) {
      final items =
          await _fetchItems(_ingrMixPath, {'pageNo': '$page'}, 500);
      if (page == 1) pageSize = items.length;
      for (final m in items) {
        final a = TabooRow._pick(m, ['INGR_KOR_NAME', 'INGR_NAME']);
        final b = TabooRow._pick(m, ['MIXTURE_INGR_KOR_NAME', 'MIXTURE_INGR_NAME']);
        if (a.isEmpty || b.isEmpty) continue;
        out.add(MixPair(a, b, TabooRow._pick(m, ['PROHBT_CONTENT', 'REMARK'])));
      }
      // 서버가 한 번에 주는 개수(100 또는 500)보다 적게 오면 마지막 페이지
      if (items.isEmpty || items.length < pageSize) break;
    }
    return out;
  }

  /// 성분 병용금기 표 (앱 실행 중 한 번만 받음). 실패하면 빈 목록.
  Future<List<MixPair>> ingredientMixTable() async {
    try {
      _mixTable ??= _loadMixTable();
      return await _mixTable!;
    } catch (_) {
      _mixTable = null;
      return [];
    }
  }

  /// DUR 성분정보: 성분 코드별 특정연령대금기 (연령 기준 포함)
  static const _ingrAgePath =
      '/1471000/DURIrdntInfoService03/getSpcifyAgrdeTabooInfoList02';

  /// 성분코드 → 연령 기준 목록. 전체가 수백 건뿐이라 한 번에 받아 둔다.
  static Future<Map<String, Set<String>>>? _ageTable;

  Future<Map<String, Set<String>>> _loadAgeTable() async {
    final table = <String, Set<String>>{};
    for (var page = 1; page <= 3; page++) {
      final uri = {'pageNo': '$page'};
      final items = await _fetchItems(_ingrAgePath, uri, 500);
      for (final m in items) {
        final code = '${m['INGR_CODE'] ?? ''}'.trim();
        final base = '${m['AGE_BASE'] ?? ''}'.trim();
        final del = '${m['DEL_YN'] ?? ''}';
        if (code.isEmpty || base.isEmpty || base == 'null' || del.contains('삭제')) continue;
        table.putIfAbsent(code, () => <String>{}).add(base);
      }
      if (items.length < 500) break;
    }
    return table;
  }

  /// 성분 코드로 연령 기준 문구(예: "12세 미만")를 찾는다. 실패하거나 없으면 빈 문자열.
  /// 같은 성분에 기준이 여럿이면 모두 이어 붙인다 (가장 넓은 기준이 적용되도록).
  Future<String> ingredientAgeBase(String ingrCode) async {
    if (ingrCode.isEmpty) return '';
    try {
      _ageTable ??= _loadAgeTable();
      final table = await _ageTable!;
      return (table[ingrCode] ?? const <String>{}).join(', ');
    } catch (_) {
      _ageTable = null; // 다음에 다시 시도
      return '';
    }
  }

  Future<List<Map<String, dynamic>>> _fetchItems(
      String path, Map<String, String> filters, int rows) async {
    final uri = Uri.https(_host, path, {
      'serviceKey': _key,
      'type': 'json',
      'pageNo': '1',
      'numOfRows': '$rows',
      ...filters,
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
    return _items(bodyMap['items']);
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
    this.ingrCode = '',
    this.className = '',
  });

  final String itemName;
  final String company;
  final String ingredient;
  final String content;
  final String remark;
  final String date;
  final String ingrCode;
  final String className;
  AgeRule rule;

  /// DUR 성분정보에서 가져온 연령 기준 (예: "12세 미만")
  String ageBase = '';

  /// 성분 단위 연령 기준이 있으면 그걸 우선한다 (품목 금기내용은 사유 위주라 나이가 빠진 경우가 많음).
  void applyAgeBase(String base) {
    ageBase = base;
    final r = AgeRule.parse(base);
    if (r.isParsed && r.conditions.any((c) => !c.assumed)) rule = r;
  }

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
      ingrCode: _pick(m, ['INGR_CODE']),
      className: ProductHit.cleanClass(_pick(m, ['CLASS_NAME'])),
    );
  }
}

/// 화면에 보여줄 간단한 약 설명
class DrugInfo {
  DrugInfo({
    required this.itemName,
    this.className = '',
    this.etcOtc = '',
    this.ingredient = '',
    this.efficacy = '',
    this.usage = '',
    this.warnings = '',
    required this.source,
  });

  final String itemName;
  final String className;
  final String etcOtc;
  final String ingredient;

  /// 효능 (e약은요 문장)
  final String efficacy;

  /// 먹는 방법 (e약은요 문장)
  final String usage;

  /// 주의사항 (e약은요 경고·주의 문장) - 사용 연령 판단에만 쓴다
  final String warnings;

  /// 연령 문구를 찾을 전체 설명문
  String get labelText => '$efficacy $usage $warnings';
  final String source;

  static String _clean(dynamic v) {
    if (v == null || '$v' == 'null') return '';
    return '$v'
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// "클로르프로칙센,,100.00,밀리그램,별규,|성분2,..." → "클로르프로칙센, 성분2"
  static String _ingredients(String raw) {
    if (!raw.contains(',')) return raw;
    return raw
        .split(RegExp(r'[|;]'))
        .map((seg) => seg.split(',').first.trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .join(', ');
  }

  factory DrugInfo.fromEasy(Map<String, dynamic> m) => DrugInfo(
        itemName: _clean(m['itemName']),
        efficacy: _clean(m['efcyQesitm']),
        usage: _clean(m['useMethodQesitm']),
        warnings: '${_clean(m['atpnWarnQesitm'])} ${_clean(m['atpnQesitm'])}'.trim(),
        source: 'e약은요',
      );

  factory DrugInfo.fromDur(Map<String, dynamic> m) => DrugInfo(
        itemName: _clean(m['ITEM_NAME']),
        className: _clean(m['CLASS_NAME']),
        etcOtc: _clean(m['ETC_OTC_NAME'] ?? m['ETC_OTC_CODE']),
        ingredient: _ingredients(_clean(m['MAIN_INGR'] ?? m['INGR_NAME'] ?? m['MATERIAL_NAME'])),
        source: 'DUR 품목정보',
      );

  /// 금기 조회 결과 행에서도 분류·성분을 얻을 수 있다.
  factory DrugInfo.fromTaboo(Map<String, dynamic> m) => DrugInfo.fromDur(m);

  bool get isEmpty =>
      efficacy.isEmpty && className.isEmpty && ingredient.isEmpty;
}

/// 검색된 제품 하나
class ProductHit {
  ProductHit({
    required this.fullName,
    this.company = '',
    this.ingredient = '',
    this.etcOtc = '',
    this.className = '',
    this.easy,
  });

  final String fullName;
  final String company;
  final String ingredient;
  final String etcOtc;

  /// 약 분류 (예: "해열.진통.소염제")
  final String className;

  /// e약은요 원본 (있으면 설명을 바로 쓸 수 있음)
  final Map<String, dynamic>? easy;

  /// 괄호 속 성분·수출명 등을 뗀 제품명. 예: "포타겔현탁액(디옥타...)" → "포타겔현탁액"
  String get displayName {
    final d = fullName.replaceFirst(RegExp(r'\s*[(\[（].*$'), '').trim();
    return d.isEmpty ? fullName : d;
  }

  /// 용량까지 뗀 검색용 이름
  String get searchName => DrugNameExtractor.toSearchName(displayName);

  static String _s(dynamic v) => (v == null || '$v' == 'null') ? '' : '$v'.trim();

  factory ProductHit.fromDur(Map<String, dynamic> m) => ProductHit(
        fullName: _s(m['ITEM_NAME']),
        company: _s(m['ENTP_NAME']),
        ingredient: DrugInfo._ingredients(_s(m['MATERIAL_NAME'] ?? m['MAIN_INGR'])),
        etcOtc: _s(m['ETC_OTC_CODE'] ?? m['ETC_OTC_NAME']),
        className: cleanClass(_s(m['CLASS_NO'] ?? m['CLASS_NAME'])),
      );

  /// "[01140]해열.진통.소염제" → "해열.진통.소염제"
  static String cleanClass(String raw) =>
      raw.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();

  factory ProductHit.fromEasy(Map<String, dynamic> m) => ProductHit(
        fullName: _s(m['itemName']),
        company: _s(m['entpName']),
        easy: m,
      );

  ProductHit withEasy(Map<String, dynamic> m) => ProductHit(
        fullName: fullName,
        company: company.isNotEmpty ? company : _s(m['entpName']),
        ingredient: ingredient,
        etcOtc: etcOtc,
        className: className,
        easy: m,
      );

  /// 빠진 정보(구분·성분·분류)를 다른 출처의 같은 제품으로 채운다.
  ProductHit fillFrom(ProductHit o) => ProductHit(
        fullName: fullName,
        company: company.isNotEmpty ? company : o.company,
        ingredient: ingredient.isNotEmpty ? ingredient : o.ingredient,
        etcOtc: etcOtc.isNotEmpty ? etcOtc : o.etcOtc,
        className: className.isNotEmpty ? className : o.className,
        easy: easy ?? o.easy,
      );
}

class Resolution {
  Resolution(this.best, this.similar,
      [this.tabooNames = const {}, this.ambiguous = false, this.tabooRows = const {}]);

  /// 후보 제품별 연령금기 행 (복용자 나이에 해당하는지 계산용)
  final Map<String, List<TabooRow>> tabooRows;
  final ProductHit? best;

  /// 비슷한 약이 여러 개라 하나로 정할 수 없음
  final bool ambiguous;
  final List<ProductHit> similar;

  /// 후보 중 연령금기 목록에 있는 제품명
  final Set<String> tabooNames;
}

class SimpleTaboo {
  SimpleTaboo({required this.ingredient, required this.content});
  final String ingredient;
  final String content;
}

class MixTaboo {
  MixTaboo({required this.partnerItem, required this.partnerIngr, required this.reason});
  final String partnerItem;
  final String partnerIngr;
  final String reason;
}

class MixPair {
  MixPair(this.a, this.b, this.reason);
  final String a;
  final String b;
  final String reason;
}
