/// 복용 리포트: 쌓인 복용 기록과 반응 기록을 모아 요약한다.
/// 사실(몇 번, 언제)만 세고, 원인이나 치료를 판단하지 않는다.
library;

import 'drug_name_extractor.dart';
import 'models.dart';
import 'reaction.dart';

/// 약 하나의 분류·성분 (복용 기록 → 식약처 자료로 확인한 값)
class DrugMeta {
  const DrugMeta({this.cls = '', this.ingredient = ''});
  final String cls;
  final String ingredient;
}

class CountItem {
  CountItem(this.name, this.count, {this.examples = const [], this.last});
  final String name;
  final int count;
  final List<String> examples;
  final DateTime? last;
}

/// "OO가 들어간 복용 N번 중 M번 '설사' 기록"
class ReactionPattern {
  ReactionPattern({
    required this.drug,
    required this.symptom,
    required this.times,
    required this.taken,
    required this.withOthers,
  });
  final String drug;
  final String symptom;

  /// 이 약이 들어간 복용 후 이 반응을 적은 횟수
  final int times;

  /// 이 약이 들어간 복용 기록 수
  final int taken;

  /// 다른 약과 함께 먹은 기록이 섞여 있어 원인을 알 수 없음
  final bool withOthers;
}

/// 증상 하나에 대한 요약: 사실(횟수·비율)만 보여주고 원인은 판단하지 않는다.
class SymptomInsight {
  SymptomInsight({
    required this.symptom,
    required this.notes,
    required this.records,
    required this.totalRecords,
    this.topDrug,
    this.contrast,
    this.direct = const [],
    this.dims = const [],
  });
  final String symptom;

  /// 이 증상을 적은 횟수
  final int notes;

  /// 이 증상이 적힌 복용 기록 수 / 전체 복용 기록 수
  final int records;
  final int totalRecords;

  /// 이 증상이 있던 복용에 가장 자주 들어 있던 약 (이름, 몇 번)
  final (String, int)? topDrug;

  /// 위 약이 들어간 복용과 안 들어간 복용의 비율:
  /// (약, 들어간 복용 중 증상 수, 들어간 복용 수, 안 들어간 복용 중 증상 수, 안 들어간 복용 수)
  final (String, int, int, int, int)? contrast;

  /// 약을 지정해 적은 기록 (약, 횟수)
  final List<(String, int)> direct;

  /// 약·성분·계열 기준으로 각각 가장 자주 함께 있던 것
  final List<SymptomDim> dims;
}

/// 반응 기록과 함께 있던 약·성분·계열 하나
class SymptomDim {
  SymptomDim({
    required this.kind,
    required this.name,
    required this.inSym,
    required this.symTotal,
    required this.withTotal,
    required this.withoutSym,
    required this.withoutTotal,
  });

  /// '약' · '성분' · '계열'
  final String kind;
  final String name;

  /// 이 반응이 있던 복용 [symTotal]번 중 이것이 있던 횟수
  final int inSym;
  final int symTotal;

  /// 이것이 들어간 복용 수 (그중 반응 기록 = [inSym])
  final int withTotal;

  /// 이것이 안 들어간 복용 중 반응 기록 수 / 안 들어간 복용 수
  final int withoutSym;
  final int withoutTotal;
}

/// 성분 이름 비교용: 띄어쓰기·염·수화물 표기를 뗀다 (아목시실린수화물 → 아목시실린)
String baseIngredient(String s) {
  var b = s.replaceAll(RegExp(r'\s'), '').toLowerCase();
  final salt = RegExp(r'(이수화물|삼수화물|수화물|무수물|나트륨|칼륨|칼슘|염산염|황산염|말레산염|타르타르산염|hydrate|sodium|potassium|hydrochloride)$');
  while (salt.hasMatch(b) && b.length > 3) {
    b = b.replaceFirst(salt, '');
  }
  return b;
}

/// 생활 관리·영양제 참고 (약사와 상의하도록 안내하는 일반 정보)
class CareTip {
  CareTip(this.title, this.body, this.because);
  final String title;
  final String body;

  /// 이 팁을 보여주는 이유 (예: "항생제 계열 6번")
  final String because;
}

class MedReport {
  MedReport({
    required this.records,
    required this.rxCount,
    required this.otcCount,
    required this.drugKinds,
    required this.reactionCount,
    required this.from,
    required this.to,
    required this.topClasses,
    required this.topDrugs,
    required this.monthly,
    required this.patterns,
    required this.tips,
    required this.unknownClass,
    this.insights = const [],
  });

  /// 증상별 요약 (많이 적은 증상부터)
  final List<SymptomInsight> insights;

  final int records;
  final int rxCount;
  final int otcCount;
  final int drugKinds;
  final int reactionCount;
  final DateTime? from;
  final DateTime? to;
  final List<CountItem> topClasses;
  final List<CountItem> topDrugs;

  /// 최근 12개월 (월, 복용 기록 수) — 오래된 달부터
  final List<(DateTime, int)> monthly;
  final List<ReactionPattern> patterns;
  final List<CareTip> tips;

  /// 분류를 확인하지 못한 약 이름
  final List<String> unknownClass;
}

String drugKey(String name) {
  final noParen = name.replaceFirst(RegExp(r'\s*[(\[（].*$'), '');
  return DrugNameExtractor.toSearchName(noParen.isEmpty ? name : noParen);
}

/// 분류 이름을 사람이 읽기 좋게: "[02220]진해거담제" → "진해거담제", "해열.진통.소염제" → "해열·진통·소염제"
String prettyClass(String raw) => raw
    .replaceAll(RegExp(r'\[[^\]]*\]'), '')
    .replaceAll('.', '·')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// 복용 기록에 적힌 이름 → 확정된 제품명 (지난 확인 결과가 있으면 그 이름)
String resolvedName(MedRecord r, String query) {
  for (final d in r.last?.drugs ?? const []) {
    if (d.query == query && !d.needsPick) return d.title;
  }
  return query;
}

MedReport buildReport(
  List<MedRecord> records,
  List<ReactionNote> notes,
  Map<String, DrugMeta> meta, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final classCount = <String, int>{};
  final classExamples = <String, Set<String>>{};
  final drugCount = <String, int>{};
  final drugName = <String, String>{};
  final drugLast = <String, DateTime>{};
  final unknown = <String>{};
  DateTime? from, to;

  for (final r in records) {
    if (from == null || r.createdAt.isBefore(from)) from = r.createdAt;
    if (to == null || r.createdAt.isAfter(to)) to = r.createdAt;
    final classesInRecord = <String>{};
    final drugsInRecord = <String>{};
    for (final q in r.drugs) {
      final name = resolvedName(r, q);
      final k = drugKey(name);
      if (k.isEmpty) continue;
      drugsInRecord.add(k);
      drugName.putIfAbsent(k, () => name);
      final last = drugLast[k];
      if (last == null || r.createdAt.isAfter(last)) drugLast[k] = r.createdAt;
      final cls = prettyClass(meta[k]?.cls ?? '');
      if (cls.isEmpty) {
        unknown.add(name);
      } else {
        classesInRecord.add(cls);
        classExamples.putIfAbsent(cls, () => <String>{}).add(name);
      }
    }
    for (final k in drugsInRecord) {
      drugCount[k] = (drugCount[k] ?? 0) + 1;
    }
    for (final c in classesInRecord) {
      classCount[c] = (classCount[c] ?? 0) + 1;
    }
  }

  List<CountItem> top(Map<String, int> m, CountItem Function(String, int) f) {
    final e = m.entries.toList()
      ..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
    return e.take(5).map((x) => f(x.key, x.value)).toList();
  }

  final topClasses = top(
      classCount,
      (k, v) => CountItem(k, v,
          examples: (classExamples[k] ?? const <String>{}).take(3).toList()));
  final topDrugs = top(drugCount,
      (k, v) => CountItem(drugName[k] ?? k, v, last: drugLast[k]));

  // 최근 12개월 월별 복용 기록 수
  final monthly = <(DateTime, int)>[];
  for (var i = 11; i >= 0; i--) {
    final m = DateTime(today.year, today.month - i);
    final n = records
        .where((r) => r.createdAt.year == m.year && r.createdAt.month == m.month)
        .length;
    monthly.add((m, n));
  }

  // 반응 패턴: 약(이름 기준)마다 증상별로 센다
  final pat = <String, Map<String, (int, bool)>>{};
  for (final n in notes) {
    final involved = n.isGroup
        ? n.items.map((e) => e.$1).toList()
        : [n.drug];
    final symptoms = n.symptoms.isEmpty ? ['메모한 반응'] : n.symptoms;
    for (final d in involved) {
      final k = drugKey(d);
      if (k.isEmpty) continue;
      drugName.putIfAbsent(k, () => d);
      final bySym = pat.putIfAbsent(k, () => {});
      for (final s in symptoms) {
        final (c, others) = bySym[s] ?? (0, false);
        bySym[s] = (c + 1, others || n.isGroup);
      }
    }
  }
  final patterns = <ReactionPattern>[];
  pat.forEach((k, bySym) {
    bySym.forEach((s, v) {
      patterns.add(ReactionPattern(
        drug: drugName[k] ?? k,
        symptom: s,
        times: v.$1,
        taken: drugCount[k] ?? 0,
        withOthers: v.$2,
      ));
    });
  });
  patterns.sort((a, b) => b.times != a.times ? b.times.compareTo(a.times) : a.drug.compareTo(b.drug));

  return MedReport(
    records: records.length,
    rxCount: records.where((r) => !r.otc).length,
    otcCount: records.where((r) => r.otc).length,
    drugKinds: drugCount.length,
    reactionCount: notes.length,
    from: from,
    to: to,
    topClasses: topClasses,
    topDrugs: topDrugs,
    monthly: monthly,
    patterns: patterns,
    tips: careTips(classCount),
    unknownClass: unknown.toList(),
    insights: symptomInsights(records, notes, meta),
  );
}

/// 받침에 맞는 조사: withJosa('세토펜', '이', '가') → "세토펜이"
String withJosa(String w, String a, String b) {
  if (w.isEmpty) return w;
  final c = w.codeUnitAt(w.length - 1);
  if (c < 0xAC00 || c > 0xD7A3) return '$w$a($b)';
  return (c - 0xAC00) % 28 != 0 ? '$w$a' : '$w$b';
}

/// 반응 기록을 복용 기록과 맞춰 증상별로 요약한다.
List<SymptomInsight> symptomInsights(List<MedRecord> records, List<ReactionNote> notes,
    [Map<String, DrugMeta> meta = const {}]) {
  final byId = {for (final r in records) r.id: r};
  // 복용 기록마다 들어 있던 약
  final drugsOf = <String, Set<String>>{};
  final nameOf = <String, String>{};
  for (final r in records) {
    final set = <String>{};
    for (final q in r.drugs) {
      final name = resolvedName(r, q);
      final k = drugKey(name);
      if (k.isEmpty) continue;
      set.add(k);
      nameOf.putIfAbsent(k, () => k);
    }
    drugsOf[r.id] = set;
  }
  // 복용 기록마다 들어 있던 성분·계열 (약 분류 자료가 있는 약만)
  final ingrOf = <String, Set<String>>{};
  final clsOf = <String, Set<String>>{};
  final ingrName = <String, String>{};
  for (final r in records) {
    final ingr = <String>{}, cls = <String>{};
    for (final k in drugsOf[r.id] ?? const <String>{}) {
      final m = meta[k];
      if (m == null) continue;
      for (final part in m.ingredient.split(RegExp(r'[,/·+]'))) {
        final t = part.trim();
        if (t.length < 2) continue;
        final b = baseIngredient(t);
        ingr.add(b);
        ingrName.putIfAbsent(b, () => t);
      }
      final c = prettyClass(m.cls);
      if (c.isNotEmpty) cls.add(c);
    }
    ingrOf[r.id] = ingr;
    clsOf[r.id] = cls;
  }
  final symptoms = <String, List<ReactionNote>>{};
  for (final n in notes) {
    for (final s in (n.symptoms.isEmpty ? ['기타 반응'] : n.symptoms)) {
      symptoms.putIfAbsent(s, () => []).add(n);
    }
  }
  final out = <SymptomInsight>[];
  final total = records.length;
  symptoms.forEach((sym, list) {
    final recIds = {
      for (final n in list)
        if (byId.containsKey(n.recordId)) n.recordId
    };
    // 증상이 있던 복용에 들어 있던 약 세기
    final inSym = <String, int>{};
    for (final id in recIds) {
      for (final k in drugsOf[id] ?? const <String>{}) {
        inSym[k] = (inSym[k] ?? 0) + 1;
      }
    }
    // 이 반응이 있던 복용에 가장 자주 들어 있던 약 하나를 고르고 (같으면 차이가 큰 약),
    // 그 약이 들어간 복용과 안 들어간 복용의 비율을 함께 보여준다 (같은 약으로 일관되게)
    (String, int)? topDrug;
    (String, int, int, int, int)? contrast;
    if (inSym.isNotEmpty && recIds.length >= 2) {
      double gapOf(String k) {
        final withTotal = drugsOf.values.where((d) => d.contains(k)).length;
        final withoutTotal = total - withTotal;
        if (withTotal == 0 || withoutTotal == 0) return -1;
        return inSym[k]! / withTotal - (recIds.length - inSym[k]!) / withoutTotal;
      }

      final maxCount = inSym.values.reduce((a, b) => a > b ? a : b);
      final ties = inSym.keys.where((k) => inSym[k] == maxCount).toList()
        ..sort((x, y) => gapOf(y).compareTo(gapOf(x)));
      final k = ties.first;
      if (maxCount >= 2) {
        topDrug = (nameOf[k] ?? k, maxCount);
        final withTotal = drugsOf.values.where((d) => d.contains(k)).length;
        final withoutTotal = total - withTotal;
        if (withoutTotal > 0) {
          contrast = (nameOf[k] ?? k, maxCount, withTotal, recIds.length - maxCount, withoutTotal);
        }
      }
    }
    // 약을 지정해 적은 기록
    final direct = <String, int>{};
    for (final n in list.where((n) => !n.isGroup)) {
      final short = drugKey(n.drug);
      direct[short] = (direct[short] ?? 0) + 1;
    }
    final directList = direct.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    // 약·성분·계열마다 이 반응과 가장 자주 함께 있던 것 하나씩
    SymptomDim? topOf(String kind, Map<String, Set<String>> setsOf, String Function(String) label) {
      if (recIds.length < 2) return null;
      final cnt = <String, int>{};
      for (final id in recIds) {
        for (final x in setsOf[id] ?? const <String>{}) {
          cnt[x] = (cnt[x] ?? 0) + 1;
        }
      }
      if (cnt.isEmpty) return null;
      int withTotalOf(String x) => setsOf.values.where((v) => v.contains(x)).length;
      double gap(String x) {
        final wt = withTotalOf(x), wo = total - wt;
        if (wt == 0 || wo == 0) return -1;
        return cnt[x]! / wt - (recIds.length - cnt[x]!) / wo;
      }

      final maxC = cnt.values.reduce((a, b) => a > b ? a : b);
      if (maxC < 2) return null;
      final ties = cnt.keys.where((x) => cnt[x] == maxC).toList()
        ..sort((a, b) => gap(b).compareTo(gap(a)));
      final x = ties.first;
      final wt = withTotalOf(x);
      return SymptomDim(
        kind: kind,
        name: label(x),
        inSym: maxC,
        symTotal: recIds.length,
        withTotal: wt,
        withoutSym: recIds.length - maxC,
        withoutTotal: total - wt,
      );
    }

    final dims = <SymptomDim>[
      for (final d in [
        topOf('약', drugsOf, (k) => nameOf[k] ?? k),
        topOf('성분', ingrOf, (k) => ingrName[k] ?? k),
        topOf('계열', clsOf, (k) => k),
      ])
        if (d != null) d,
    ];

    out.add(SymptomInsight(
      dims: dims,
      symptom: sym,
      notes: list.length,
      records: recIds.length,
      totalRecords: total,
      topDrug: topDrug,
      contrast: contrast,
      direct: directList.take(3).toList(),
    ));
  });
  out.sort((a, b) => b.notes.compareTo(a.notes));
  return out;
}

/// 자주 먹은 약 계열에 따른 일반적인 생활 관리·영양제 참고.
/// 진단·처방이 아니라 "약사·의사와 상의해 볼 만한 것"만 알려준다.
List<CareTip> careTips(Map<String, int> classCount) {
  int count(List<String> keys) {
    var n = 0;
    classCount.forEach((c, v) {
      if (keys.any(c.contains)) n += v;
    });
    return n;
  }

  final tips = <CareTip>[];
  final abx = count(['항생', '그람양성', '그람음성', '항균']);
  if (abx >= 2) {
    tips.add(CareTip(
      '유산균(프로바이오틱스)',
      '항생제를 먹을 때 장 건강을 위해 유산균을 함께 챙기는 경우가 많아요. 항생제와 먹는 시간 간격은 약사에게 확인하세요.',
      '항생제 계열 $abx번',
    ));
  }
  final gut = count(['정장', '지사', '소화', '제산', '위장']);
  if (gut >= 2) {
    tips.add(CareTip(
      '장 건강 관리',
      '장·소화기 약을 자주 먹었다면 유산균이나 식이섬유가 도움이 되는지 약사와 상의해 보세요. 설사가 잦으면 수분 보충이 가장 중요해요.',
      '소화기 계열 $gut번',
    ));
  }
  final steroid = count(['부신피질', '스테로이드', '호르몬']);
  if (steroid >= 2) {
    tips.add(CareTip(
      '비타민D·칼슘 상담',
      '먹는 스테로이드를 자주 쓰면 뼈 건강을 위해 비타민D·칼슘을 챙기기도 해요. 필요한지는 다음 진료 때 의사와 상의하세요.',
      '부신피질호르몬 계열 $steroid번',
    ));
  }
  final resp = count(['진해', '거담', '기침', '알레르기', '항히스타민', '호흡']);
  if (resp >= 3) {
    tips.add(CareTip(
      '호흡기 생활 관리',
      '기침·가래·알레르기 약을 자주 먹었다면 실내 습도(40~60%)와 충분한 물 마시기가 도움이 돼요. 계속 반복되면 소아청소년과·알레르기 진료를 상의해 보세요.',
      '호흡기·알레르기 계열 $resp번',
    ));
  }
  final fever = count(['해열', '진통']);
  if (fever >= 4) {
    tips.add(CareTip(
      '해열제 복용 기록',
      '해열·진통제를 자주 먹었어요. 열이 자주 나거나 오래가면 원인을 확인하도록 진료를 받아보세요.',
      '해열·진통 계열 $fever번',
    ));
  }
  return tips;
}
