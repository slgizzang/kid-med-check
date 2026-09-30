/// 복용 후 반응 기록: 보호자가 적어둔 메모를 다음 처방 때 다시 보여준다.
/// 앱은 약이 원인인지 판단하지 않는다. 기록한 사실만 보여주고 의사·약사에게 알리도록 안내한다.
library;

import 'drug_name_extractor.dart';

/// 고를 수 있는 증상 (그 외는 메모로)
const kReactionSymptoms = [
  '설사', '구토', '복통', '발진·두드러기', '가려움', '졸림', '흥분·잠 못 잠', '열', '기타',
];

class ReactionNote {
  ReactionNote({
    required this.id,
    required this.childId,
    required this.drug,
    required this.date,
    this.recordId = '',
    this.ingredient = '',
    this.symptoms = const [],
    this.memo = '',
    this.items = const [],
  });

  /// 처방 전체에 적은 기록이면 함께 먹은 약들 (이름, 성분). 약 하나에 적은 기록이면 비어 있음.
  final List<(String, String)> items;

  bool get isGroup => items.isNotEmpty;

  final String id;
  final String childId;

  /// 어느 처방 기록에서 적었는지 (없으면 빈 문자열)
  final String recordId;

  /// 약 이름(확정된 제품명)과 성분
  final String drug;
  final String ingredient;
  final DateTime date;
  final List<String> symptoms;
  final String memo;

  /// "설사, 구토 · 메모"
  String get summary {
    final s = symptoms.join(', ');
    final m = memo.trim();
    if (s.isEmpty) return m;
    if (m.isEmpty) return s;
    return '$s · $m';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'child': childId,
        'rec': recordId,
        'drug': drug,
        'ingr': ingredient,
        'at': date.toIso8601String(),
        'sym': symptoms,
        'memo': memo,
        if (items.isNotEmpty) 'items': [for (final (n, i) in items) [n, i]],
      };

  factory ReactionNote.fromJson(Map<String, dynamic> j) => ReactionNote(
        id: '${j['id']}',
        childId: '${j['child']}',
        recordId: '${j['rec'] ?? ''}',
        drug: '${j['drug']}',
        ingredient: '${j['ingr'] ?? ''}',
        date: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
        symptoms: (j['sym'] as List? ?? const []).map((e) => '$e').toList(),
        memo: '${j['memo'] ?? ''}',
        items: [
          for (final e in (j['items'] as List? ?? const []))
            if (e is List && e.isNotEmpty) ('${e[0]}', e.length > 1 ? '${e[1]}' : '')
        ],
      );
}

enum ReactionMatch { sameDrug, sameIngredient }

/// 이름 비교용: 괄호·공백·용량을 뗀다.
String _normName(String name) {
  final noParen = name.replaceFirst(RegExp(r'\s*[(\[（].*$'), '');
  return DrugNameExtractor.toSearchName(noParen.isEmpty ? name : noParen);
}

Set<String> _ingrSet(String text) => text
    .split(RegExp(r'[,/·+|;]'))
    .map((x) => x.replaceAll(RegExp(r'\s'), '').toLowerCase())
    .where((x) => x.length >= 2)
    .toSet();

ReactionMatch? _match1(String noteDrug, String noteIngr, String drug, String ingredient) {
  final a = _normName(noteDrug), b = _normName(drug);
  if (a.isNotEmpty && a == b) return ReactionMatch.sameDrug;
  final shared = _ingrSet(noteIngr).intersection(_ingrSet(ingredient));
  if (shared.isNotEmpty) return ReactionMatch.sameIngredient;
  return null;
}

/// 이 약(이름·성분)이 기록과 같은 약인지, 같은 성분이 든 약인지.
/// 처방 전체 기록이면 함께 먹은 약 중 하나라도 해당하는지 본다.
ReactionMatch? matchReaction(ReactionNote n, String drug, String ingredient) {
  if (!n.isGroup) return _match1(n.drug, n.ingredient, drug, ingredient);
  ReactionMatch? best;
  for (final (name, ingr) in n.items) {
    final m = _match1(name, ingr, drug, ingredient);
    if (m == ReactionMatch.sameDrug) return m;
    best ??= m;
  }
  return best;
}

/// 기록 한 줄 문구. 처방 전체 기록이면 함께 먹은 약을 밝히고 원인을 단정하지 않는다.
String reactionLine(ReactionNote n, ReactionMatch m) {
  final d = formatReactionDate(n.date);
  if (n.isGroup) {
    final names = n.items.map((e) => e.$1).join(', ');
    return '$d 함께 먹은 약($names) 복용 후 · ${n.summary}';
  }
  return m == ReactionMatch.sameDrug
      ? '$d 복용 후 · ${n.summary}'
      : '$d 같은 성분의 ${n.drug} 복용 후 · ${n.summary}';
}

/// 이 약과 관련된 기록 (최근 것부터)
List<(ReactionNote, ReactionMatch)> reactionsFor(
    List<ReactionNote> notes, String drug, String ingredient) {
  final out = <(ReactionNote, ReactionMatch)>[];
  for (final n in notes) {
    final m = matchReaction(n, drug, ingredient);
    if (m != null) out.add((n, m));
  }
  out.sort((x, y) => y.$1.date.compareTo(x.$1.date));
  return out;
}

String formatReactionDate(DateTime d) => '${d.year}.${d.month}.${d.day}';
