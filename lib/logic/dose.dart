/// 처방 용량·기간과 식약처 DUR 용량주의(1일 최대 투여량)·투여기간주의(최대 투여기간) 대조.
///
/// - 처방 용량: 심평원 투약이력 파일의 '1회 투약량', '1일 투여횟수', '총 투약일수', '단위'
/// - 기준: DUR 성분정보(assets/dur_dose.json, 성분코드별). 약의 성분코드는 DUR 품목정보에서 얻는다.
///
/// 하루 양(mg)은 단일 성분 정제·캡슐처럼 한 알의 함량이 제품명에 하나만 적혀 있을 때만 계산한다.
/// 시럽·가루약·복합제처럼 함량을 확실히 알 수 없으면 계산하지 않고 기준과 처방 내용만 보여준다.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 한 약의 처방 용량 (심평원 투약이력)
class DoseInfo {
  const DoseInfo({this.unit = '', this.perDose, this.timesPerDay, this.days});

  /// 투약 단위 (정, 캡슐, mL, g, 포 …)
  final String unit;

  /// 1회 투약량 (단위 기준)
  final double? perDose;

  /// 1일 투여횟수
  final int? timesPerDay;

  /// 총 투약일수
  final int? days;

  bool get isEmpty => perDose == null && timesPerDay == null && days == null;

  /// 하루 투약량 (단위 기준)
  double? get perDay =>
      perDose != null && timesPerDay != null ? perDose! * timesPerDay! : null;

  /// "1회 1정 · 하루 3번 · 3일"
  String get label => [
        if (perDose != null) '1회 ${fmtNum(perDose!)}${unit.isEmpty ? '' : unitLabel(unit)}',
        if (timesPerDay != null) '하루 $timesPerDay번',
        if (days != null) '$days일',
      ].join(' · ');

  Map<String, dynamic> toJson() => {
        if (unit.isNotEmpty) 'u': unit,
        if (perDose != null) 'q': perDose,
        if (timesPerDay != null) 'n': timesPerDay,
        if (days != null) 'd': days,
      };

  factory DoseInfo.fromJson(Map<String, dynamic> j) => DoseInfo(
        unit: '${j['u'] ?? ''}',
        perDose: (j['q'] as num?)?.toDouble(),
        timesPerDay: (j['n'] as num?)?.toInt(),
        days: (j['d'] as num?)?.toInt(),
      );

  /// 파일 칸 값으로 만든다. 숫자를 못 읽으면 그 항목은 비워 둔다.
  static DoseInfo? parse(
      {String unit = '', String perDose = '', String times = '', String days = ''}) {
    final d = DoseInfo(
      unit: unit.trim(),
      perDose: _num(perDose),
      timesPerDay: _num(times)?.round(),
      days: _num(days)?.round(),
    );
    return d.isEmpty ? null : d;
  }

  static double? _num(String s) {
    final m = RegExp(r'\d+(?:\.\d+)?').firstMatch(s.replaceAll(',', ''));
    if (m == null) return null;
    final v = double.tryParse(m.group(0)!);
    return v == null || v <= 0 ? null : v;
  }
}

String fmtNum(double v) {
  if (v == v.roundToDouble()) return _comma(v.round());
  var s = v.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}

String _comma(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// 파일의 단위 표기를 짧게 (mL, 정 …)
String unitLabel(String u) {
  final t = u.trim();
  final l = t.toLowerCase();
  if (l == 'ml' || t == '밀리리터') return 'mL';
  if (l == 'g' || t == '그램') return 'g';
  if (l == 'mg' || t == '밀리그램' || t == '밀리그람') return 'mg';
  return t;
}

/// 정제·캡슐처럼 한 알 단위인지
bool isUnitDose(String unit) {
  final u = unit.replaceAll(RegExp(r'\s'), '');
  return const ['정', '캡슐', '캅셀', '캡', '알', 'T', 'C', 'TAB', 'CAP']
      .any((x) => u.toUpperCase() == x.toUpperCase());
}

/// "4,000밀리그램", "아세트아미노펜 4,000밀리그램", "3그램", "0.25mg" → mg. 숫자가 둘 이상이면 null.
double? maxMg(String text) {
  final t = text.replaceAll(',', '');
  final all = RegExp(r'(\d+(?:\.\d+)?)\s*(마이크로그램|마이크로그람|밀리그램|밀리그람|mg|㎎|그램|그람|g|㎍|mcg)',
          caseSensitive: false)
      .allMatches(t)
      .toList();
  if (all.length != 1) return null;
  if (RegExp(r'\d').allMatches(t).length >
      RegExp(r'\d').allMatches(all.first.group(0)!).length) {
    return null; // 다른 숫자(함량 조건 등)가 섞여 있으면 계산하지 않음
  }
  return _toMg(double.parse(all.first.group(1)!), all.first.group(2)!);
}

double _toMg(double v, String unit) {
  final u = unit.toLowerCase();
  if (u.startsWith('마이크로') || u == '㎍' || u == 'mcg') return v / 1000;
  if (u.startsWith('밀리') || u == 'mg' || u == '㎎') return v;
  return v * 1000; // 그램
}

/// 제품명에 적힌 한 알의 함량(mg). "타이레놀정500밀리그람" → 500. 함량이 없거나 둘 이상이면 null.
double? strengthMg(String productName) {
  final t = productName.replaceAll(',', '').replaceFirst(RegExp(r'[(\[（].*$'), '');
  final all = RegExp(r'(\d+(?:\.\d+)?)\s*(마이크로그램|마이크로그람|밀리그램|밀리그람|mg|㎎|그램|그람|g)',
          caseSensitive: false)
      .allMatches(t)
      .toList();
  if (all.length != 1) return null;
  // "160mg/5mL" 처럼 부피당 함량이면 한 알 함량이 아님
  if (t.substring(all.first.end).trimLeft().startsWith('/')) return null;
  return _toMg(double.parse(all.first.group(1)!), all.first.group(2)!);
}

/// "7일" → [7], "무배란증:12일, 난포과자극유도:20일" → [12, 20]
List<int> maxDays(String text) => [
      for (final m in RegExp(r'(\d+)\s*일').allMatches(text)) int.parse(m.group(1)!),
    ];

/// "4,000밀리그램" → "4,000mg"
String shortMax(String text) => text
    .replaceAll('마이크로그램', '㎍')
    .replaceAll('마이크로그람', '㎍')
    .replaceAll('밀리그램', 'mg')
    .replaceAll('밀리그람', 'mg')
    .replaceAll('밀리리터', 'mL')
    .replaceAll(RegExp(r'(?<=\d)\s*그램'), 'g')
    .trim();

class DoseEntry {
  DoseEntry({this.form = '', required this.max, this.content = '', this.remark = ''});
  final String form;
  final String max;
  final String content;
  final String remark;
}

class DoseRule {
  DoseRule({required this.code, required this.name, this.mix = '', required this.entries});
  final String code;
  final String name;

  /// 단일 / 복합
  final String mix;
  final List<DoseEntry> entries;

  /// 제품 제형에 맞는 기준만 (맞는 게 없으면 전체)
  List<DoseEntry> forForms(Set<String> forms) {
    if (forms.isEmpty) return entries;
    final mine = {for (final f in forms) formGroup(f)};
    final hit = entries
        .where((e) => e.form.isEmpty || e.form.split('/').any((p) => mine.contains(formGroup(p))))
        .toList();
    return hit.isEmpty ? entries : hit;
  }
}

/// 제형을 큰 묶음으로: "필름코팅정"·"정제" → 정, "용액주사제" → 주사 …
String formGroup(String form) {
  final f = form.replaceAll(RegExp(r'\s'), '');
  if (f.contains('주사')) return '주사';
  if (f.contains('캡슐') || f.contains('캅셀')) return '캡슐';
  if (f.endsWith('정') || f.contains('정제')) return '정';
  if (f.contains('시럽') || f.contains('현탁') || f.endsWith('액') || f.contains('액제')) return '액';
  if (f.contains('과립') || f.endsWith('산') || f.contains('산제') || f.contains('가루')) return '산';
  if (f.contains('패취') || f.contains('패치')) return '패취';
  return f;
}

/// 성분코드별 용량주의·투여기간주의 기준표
class DoseTable {
  DoseTable(this.dose, this.period);
  final Map<String, DoseRule> dose;
  final Map<String, DoseRule> period;

  static DoseTable parse(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    Map<String, DoseRule> read(String k) => {
          for (final e in (j[k] as Map? ?? const {}).entries)
            '${e.key}': DoseRule(
              code: '${e.key}',
              name: '${(e.value as Map)['n'] ?? ''}',
              mix: '${(e.value as Map)['t'] ?? ''}',
              entries: [
                for (final x in ((e.value as Map)['e'] as List? ?? const []))
                  DoseEntry(
                    form: '${(x as Map)['f'] ?? ''}',
                    max: '${x['m'] ?? ''}',
                    content: '${x['p'] ?? ''}',
                    remark: '${x['r'] ?? ''}',
                  ),
              ],
            ),
        };
    return DoseTable(read('dose'), read('period'));
  }

  static Future<DoseTable>? _loaded;

  /// 앱에 들어 있는 표 (한 번만 읽음). 못 읽으면 빈 표.
  static Future<DoseTable> load() => _loaded ??= rootBundle
      .loadString('assets/dur_dose.json')
      .then(parse)
      .catchError((_) => DoseTable(const {}, const {}));
}

enum DoseKind { dose, period }

/// 한 약에 대한 용량주의·투여기간주의 결과
class DoseFinding {
  DoseFinding({
    required this.kind,
    required this.ingredient,
    required this.max,
    this.over,
    this.amount = '',
    this.note = '',
  });

  final DoseKind kind;

  /// 기준 성분 이름
  final String ingredient;

  /// 기준 (예: "4,000mg", "7일")
  final String max;

  /// 처방이 기준을 넘는지. 계산할 수 없으면 null.
  final bool? over;

  /// 처방 기준 양 (예: "하루 1,500mg", "5일")
  final String amount;

  /// 기준의 조건 (예: "모든 제형, 단일제·복합제 포함")
  final String note;

  String get title => kind == DoseKind.dose
      ? '용량주의 · $ingredient 하루 최대 $max'
      : '투여기간주의 · $ingredient 최대 $max';
}

/// 기준 문구에서 성분 이름(숫자 앞)들. "아세트아미노펜 2,600밀리그램/트라마돌염산염 300밀리그램" → {아세트아미노펜, 트라마돌염산염}
Set<String> namesIn(String text) => {
      for (final m in RegExp(r'([가-힣]{2,})\s*[:/]?\s*\d').allMatches(text))
        m.group(1)!.replaceFirst(RegExp(r'(으로서|로서)$'), ''),
    }..removeWhere((x) => x.length < 2 || const {'최대용량', '최대', '용량', '주성분', '함량', '고령자'}.contains(x));

/// 같은 성분인지 (염 이름 차이 허용: 메토클로프라미드 ↔ 메토클로프라미드염산염)
bool sameIngr(String a, String b) {
  String n(String s) => s.replaceAll(RegExp(r'\s|\[[^\]]*\]'), '');
  final x = n(a), y = n(b);
  if (x.isEmpty || y.isEmpty) return false;
  return x.contains(y) || y.contains(x);
}

/// 제품 성분 구성에 맞는 기준만 고른다.
/// 식약처 성분표는 한 성분코드에 그 성분이 든 복합제 기준까지 함께 들어 있다
/// (예: 아세트아미노펜 코드에 '아세트아미노펜+트라마돌' 2,600mg 기준). 단일제에는 단일 기준만,
/// 복합제에는 함께 든 성분이 모두 맞는 복합 기준(없으면 단일 기준)을 쓴다.
List<DoseEntry> forProduct(DoseRule rule, List<DoseEntry> entries, List<String> productIngr) {
  Set<String> partners(DoseEntry e) =>
      {for (final n in namesIn('${e.max} ${e.content}')) if (!sameIngr(n, rule.name)) n};
  final plain = entries.where((e) => partners(e).isEmpty && e.remark != '복합제').toList();
  final others = productIngr.where((x) => !sameIngr(x, rule.name)).toList();
  if (others.isEmpty) return plain;
  final combo = entries.where((e) {
    final p = partners(e);
    return p.isNotEmpty && p.every((x) => others.any((o) => sameIngr(o, x)));
  }).toList();
  return combo.isNotEmpty ? combo : plain;
}

/// 기준 문구에서 이 성분의 최대량(mg). "아세트아미노펜 2,600밀리그램/트라마돌염산염 300밀리그램" → 2600
double? ingrMaxMg(String max, String ingr) {
  final t = max.replaceAll(',', '');
  for (final m in RegExp(r'([가-힣]{2,})\s*(\d+(?:\.\d+)?)\s*(마이크로그램|마이크로그람|밀리그램|밀리그람|mg|그램|그람|g)')
      .allMatches(t)) {
    if (sameIngr(m.group(1)!, ingr)) return _toMg(double.parse(m.group(2)!), m.group(3)!);
  }
  return maxMg(max);
}

/// 품목 DUR 목록에서 얻은 이 제품의 정보
class ItemDose {
  ItemDose({this.forms = const {}, this.ingredients = const []});

  /// 제형 (예: 필름코팅정)
  final Set<String> forms;

  /// 제품의 주성분들 (예: [아세트아미노펜, 트라마돌염산염])
  final List<String> ingredients;
}

/// DUR 기준과 처방 용량을 대조한다.
/// [doseCodes]/[periodCodes]: 이 약이 용량주의/투여기간주의 품목 목록에 오른 성분코드 → 제품 정보.
List<DoseFinding> evaluateDose({
  required DoseTable table,
  required Map<String, ItemDose> doseCodes,
  required Map<String, ItemDose> periodCodes,
  required String productName,
  DoseInfo? dose,
}) {
  final out = <DoseFinding>[];
  for (final e in doseCodes.entries) {
    final rule = table.dose[e.key];
    if (rule == null) continue;
    final ingr = e.value.ingredients.isEmpty ? [rule.name] : e.value.ingredients;
    final entries = forProduct(rule, rule.forForms(e.value.forms), ingr);
    if (entries.isEmpty) continue;
    final single = ingr.where((x) => !sameIngr(x, rule.name)).isEmpty;
    final mgs = {for (final x in entries) ingrMaxMg(x.max, rule.name)};
    final limit = mgs.length == 1 ? mgs.first : null;
    final max = limit != null
        ? '${fmtNum(limit)}mg'
        : ({for (final x in entries) shortMax(x.max)}..removeWhere((x) => x.isEmpty)).join(' / ');
    if (max.isEmpty) continue;
    final strength = single ? strengthMg(productName) : null;
    bool? over;
    var amount = '';
    final perDay = dose?.perDay;
    if (limit != null && strength != null && perDay != null && isUnitDose(dose!.unit)) {
      final mg = perDay * strength;
      amount = '하루 약 ${fmtNum(mg.roundToDouble())}mg (${fmtNum(strength)}mg 1${unitLabel(dose!.unit)} 기준)';
      over = mg > limit + 1e-6;
    }
    out.add(DoseFinding(
      kind: DoseKind.dose,
      ingredient: rule.name,
      max: max,
      over: over,
      amount: amount,
    ));
  }
  for (final e in periodCodes.entries) {
    final rule = table.period[e.key];
    if (rule == null) continue;
    final entries = rule.forForms(e.value.forms);
    final maxes = {for (final x in entries) x.max.trim()}..removeWhere((x) => x.isEmpty);
    if (maxes.isEmpty) continue;
    final days = [for (final x in entries) ...maxDays(x.max)];
    bool? over;
    final d = dose?.days;
    if (d != null && days.isNotEmpty) {
      final hi = days.reduce((a, b) => a > b ? a : b);
      final lo = days.reduce((a, b) => a < b ? a : b);
      over = d > hi ? true : (d <= lo ? false : null);
    }
    out.add(DoseFinding(
      kind: DoseKind.period,
      ingredient: rule.name,
      max: maxes.join(' / '),
      over: over,
      amount: d == null ? '' : '$d일',
    ));
  }
  return out;
}
