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
  });

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

/// 이 약(이름·성분)이 기록과 같은 약인지, 같은 성분이 든 약인지
ReactionMatch? matchReaction(ReactionNote n, String drug, String ingredient) {
  final a = _normName(n.drug), b = _normName(drug);
  if (a.isNotEmpty && a == b) return ReactionMatch.sameDrug;
  final shared = _ingrSet(n.ingredient).intersection(_ingrSet(ingredient));
  if (shared.isNotEmpty) return ReactionMatch.sameIngredient;
  return null;
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
