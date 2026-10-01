/// 확인 결과 요약(스냅샷). 결과 화면 대시보드와, 처방 기록에 저장해 다시 보여주는 데 쓴다.
library;

class DrugSnap {
  DrugSnap({
    required this.query,
    required this.title,
    this.ageRule,
    this.labelNote,
    this.preg = false,
    this.nursing = false,
    this.mixWith = const [],
    this.needsPick = false,
    this.ingredient = '',
    this.reaction,
    this.cls = '',
    this.allergy,
  });

  /// 알레르기 약물과 같은 계열이면 그 알레르기 이름 (예: "페니실린계")
  final String? allergy;

  /// 약 분류(계열). 예: "해열.진통.소염제"
  final String cls;

  /// 기록에 적힌 이름 (목록 변경 감지용)
  final String query;

  /// 확정된 제품명
  final String title;

  /// 연령금기 해당 시 기준 (예: "12세 이하")
  final String? ageRule;

  /// 설명서상 사용 연령 주의 (예: "24개월 이상 소아")
  final String? labelNote;
  final bool preg;
  final bool nursing;
  final List<String> mixWith;
  final bool needsPick;

  /// 확정된 약의 성분 (반응 기록 연결용)
  final String ingredient;

  /// 이 약(또는 같은 성분)에 대해 보호자가 적어둔 지난 반응 (예: "설사")
  final String? reaction;

  bool get isDanger => ageRule != null || preg || mixWith.isNotEmpty || allergy != null;

  /// 금기·주의·선택 필요 (반응 기록 제외)
  bool get hasAlert => isDanger || labelNote != null || nursing || needsPick;
  bool get hasAny => hasAlert || reaction != null;

  Map<String, dynamic> toJson() => {
        'q': query,
        't': title,
        if (ageRule != null) 'age': ageRule,
        if (labelNote != null) 'label': labelNote,
        'preg': preg,
        'nurse': nursing,
        'mix': mixWith,
        'pick': needsPick,
        if (ingredient.isNotEmpty) 'ingr': ingredient,
        if (cls.isNotEmpty) 'cls': cls,
        if (allergy != null) 'alg': allergy,
        if (reaction != null) 'react': reaction,
      };

  factory DrugSnap.fromJson(Map<String, dynamic> j) => DrugSnap(
        query: '${j['q']}',
        title: '${j['t']}',
        ageRule: j['age'] as String?,
        labelNote: j['label'] as String?,
        preg: j['preg'] == true,
        nursing: j['nurse'] == true,
        mixWith: (j['mix'] as List? ?? const []).map((e) => '$e').toList(),
        needsPick: j['pick'] == true,
        ingredient: '${j['ingr'] ?? ''}',
        cls: '${j['cls'] ?? ''}',
        allergy: j['alg'] as String?,
        reaction: j['react'] as String?,
      );
}

class ResultSnapshot {
  ResultSnapshot({
    required this.at,
    required this.drugs,
    required this.mixPairs,
    required this.pregnant,
    required this.nursing,
    this.ageMonths,
    this.allergies = const [],
  });

  /// 확인 당시 복용자 알레르기 목록
  final List<String> allergies;

  /// 확인에 쓴 나이(개월) — 처방일 기준
  final int? ageMonths;

  final DateTime at;
  final List<DrugSnap> drugs;

  /// 병용금기 조합 ("A + B")
  final List<String> mixPairs;

  /// 확인 당시 사용자 상태
  final bool pregnant;
  final bool nursing;

  int get ageCount => drugs.where((d) => d.ageRule != null).length;
  int get pregCount => drugs.where((d) => d.preg).length;
  int get nursingCount => drugs.where((d) => d.nursing).length;
  int get labelCount => drugs.where((d) => d.labelNote != null).length;
  int get pickCount => drugs.where((d) => d.needsPick).length;
  int get allergyCount => drugs.where((d) => d.allergy != null).length;
  int get reactionCount => drugs.where((d) => d.reaction != null).length;

  /// 기록의 약 목록이 확인 당시와 같은지
  bool matches(List<String> current) {
    final a = drugs.map((d) => d.query).toSet();
    final b = current.toSet();
    return a.length == b.length && a.containsAll(b);
  }

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'drugs': drugs.map((d) => d.toJson()).toList(),
        'mix': mixPairs,
        'preg': pregnant,
        'nurse': nursing,
        if (ageMonths != null) 'age': ageMonths,
        if (allergies.isNotEmpty) 'alg': allergies,
      };

  factory ResultSnapshot.fromJson(Map<String, dynamic> j) => ResultSnapshot(
        at: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
        drugs: (j['drugs'] as List? ?? const [])
            .map((e) => DrugSnap.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        mixPairs: (j['mix'] as List? ?? const []).map((e) => '$e').toList(),
        pregnant: j['preg'] == true,
        nursing: j['nurse'] == true,
        ageMonths: j['age'] is int ? j['age'] as int : null,
        allergies: (j['alg'] as List? ?? const []).map((e) => '$e').toList(),
      );
}
