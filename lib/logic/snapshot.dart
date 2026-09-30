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
  });

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

  bool get isDanger => ageRule != null || preg || mixWith.isNotEmpty;
  bool get hasAny => isDanger || labelNote != null || nursing || needsPick;

  Map<String, dynamic> toJson() => {
        'q': query,
        't': title,
        if (ageRule != null) 'age': ageRule,
        if (labelNote != null) 'label': labelNote,
        'preg': preg,
        'nurse': nursing,
        'mix': mixWith,
        'pick': needsPick,
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
      );
}

class ResultSnapshot {
  ResultSnapshot({
    required this.at,
    required this.drugs,
    required this.mixPairs,
    required this.pregnant,
    required this.nursing,
  });

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
      };

  factory ResultSnapshot.fromJson(Map<String, dynamic> j) => ResultSnapshot(
        at: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
        drugs: (j['drugs'] as List? ?? const [])
            .map((e) => DrugSnap.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        mixPairs: (j['mix'] as List? ?? const []).map((e) => '$e').toList(),
        pregnant: j['preg'] == true,
        nursing: j['nurse'] == true,
      );
}
