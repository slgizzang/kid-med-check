import 'dur_api.dart';
import 'label_age.dart';
import 'snapshot.dart';

class ChildProfile {
  ChildProfile({
    required this.id,
    required this.name,
    required this.birthDate,
    this.pregnant = false,
    this.nursing = false,
  });

  final String id;
  final String name;
  final DateTime birthDate;

  /// 임신 중 (성인만)
  final bool pregnant;

  /// 수유 중 (성인만)
  final bool nursing;

  /// 만 19세 이상
  bool get isAdult => ageInMonths() >= 19 * 12;

  int ageInMonths([DateTime? now]) => monthsBetween(birthDate, now ?? DateTime.now());

  String get ageLabel => formatAge(ageInMonths());

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'birth': birthDate.toIso8601String(),
        'pregnant': pregnant,
        'nursing': nursing,
      };

  factory ChildProfile.fromJson(Map<String, dynamic> j) => ChildProfile(
        id: '${j['id']}',
        name: '${j['name']}',
        birthDate: DateTime.parse('${j['birth']}'),
        pregnant: j['pregnant'] == true,
        nursing: j['nursing'] == true,
      );
}

class Interaction {
  Interaction(this.other, this.reason);
  final String other;
  final String reason;
}

/// 처방 기록(버전). 아이별로 여러 개를 저장해두고 약을 계속 추가·수정할 수 있다.
class MedRecord {
  MedRecord({
    required this.id,
    required this.childId,
    required this.title,
    required this.createdAt,
    List<String>? drugs,
    this.last,
  }) : drugs = drugs ?? [];

  final String id;
  final String childId;
  String title;
  final DateTime createdAt;
  final List<String> drugs;

  /// 마지막 확인 결과 (없으면 null)
  ResultSnapshot? last;

  static String defaultTitle(DateTime d) => '${d.month}월 ${d.day}일 처방';

  Map<String, dynamic> toJson() => {
        'id': id,
        'childId': childId,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'drugs': drugs,
        if (last != null) 'last': last!.toJson(),
      };

  factory MedRecord.fromJson(Map<String, dynamic> j) => MedRecord(
        id: '${j['id']}',
        childId: '${j['childId']}',
        title: '${j['title']}',
        createdAt: DateTime.tryParse('${j['createdAt']}') ?? DateTime.now(),
        drugs: (j['drugs'] as List? ?? const []).map((e) => '$e').toList(),
        last: j['last'] is Map
            ? ResultSnapshot.fromJson(Map<String, dynamic>.from(j['last'] as Map))
            : null,
      );
}

String formatDate(DateTime d) =>
    '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

int monthsBetween(DateTime birth, DateTime now) {
  var m = (now.year - birth.year) * 12 + (now.month - birth.month);
  if (now.day < birth.day) m -= 1;
  return m < 0 ? 0 : m;
}

String formatAge(int months) {
  final y = months ~/ 12;
  final mo = months % 12;
  if (y == 0) return '생후 $mo개월';
  return mo == 0 ? '만 $y세' : '만 $y세 $mo개월';
}

enum CheckStatus { loading, danger, labelCaution, notFound, unknown, listedOk, notListed, error }

class DrugCheck {
  DrugCheck(this.query);

  final String query;
  CheckStatus status = CheckStatus.loading;
  List<TabooRow> rows = const [];
  String? error;

  /// 실제로 결과를 찾은 검색어 (원래 이름으로 못 찾아 줄여서 찾은 경우 다름)
  String? matchedQuery;

  /// 입력한 이름과 가장 비슷한 실제 제품 (못 찾으면 null)
  ProductHit? best;

  /// "혹시 찾으시는 약이 이것인가요?" 후보
  List<ProductHit> similar = const [];

  /// 후보 중 연령금기 목록에 있는 제품명 (후보 칩에 표시)
  Set<String> tabooNames = const {};

  /// 입력한 이름에 맞는 약이 여러 개라 골라야 함
  bool ambiguous = false;

  /// 이 약의 성분 (병용금기 대조용)
  String ingredientText = '';

  /// DUR 임부금기 (임신 중인 사람일 때만 조회)
  List<SimpleTaboo> pregRows = const [];

  /// 설명서의 수유부 주의 문장 (수유 중일 때만)
  String? nursingNote;

  /// DUR 병용금기 원자료
  List<MixTaboo> mixRows = const [];

  /// 같은 기록 안에서 함께 먹으면 안 되는 약들
  List<Interaction> interactions = [];

  bool get hasPreg => pregRows.isNotEmpty;
  bool get hasMix => interactions.isNotEmpty;

  /// 빨간 경고가 필요한지 (연령금기·임부금기·병용금기)
  bool get isDanger => status == CheckStatus.danger || hasPreg || hasMix;

  /// 카드 제목: 찾은 정확한 제품명, 없으면 입력한 이름
  String get title => best?.displayName ?? query;

  /// 약 설명 (없을 수 있음)
  DrugInfo? info;
  bool infoLoading = true;

  /// 설명서(e약은요)상 사용 연령보다 어린 경우의 근거
  LabelAgeFinding? labelFinding;

  /// 약 설명을 받은 뒤 설명서상 사용 연령도 확인한다. DUR 연령금기가 우선.
  void applyLabel(int ageMonths) {
    labelFinding = null;
    final i = info;
    if (i == null) return;
    labelFinding = LabelAge.check(i.labelText, ageMonths);
    if (labelFinding != null &&
        (status == CheckStatus.notListed ||
            status == CheckStatus.listedOk ||
            status == CheckStatus.unknown)) {
      status = CheckStatus.labelCaution;
    }
  }

  /// 결과 행 중 아이 나이에 금기로 해당하는 것
  List<TabooRow> dangerRows(int ageMonths) =>
      rows.where((r) => r.rule.appliesTo(ageMonths) == true).toList();

  void evaluate(int ageMonths) {
    if (rows.isEmpty) {
      status = CheckStatus.notListed;
      return;
    }
    final results = rows.map((r) => r.rule.appliesTo(ageMonths)).toList();
    if (results.contains(true)) {
      status = CheckStatus.danger;
    } else if (results.contains(null)) {
      status = CheckStatus.unknown;
    } else {
      status = CheckStatus.listedOk;
    }
  }
}

/// e약은요 효능 문장을 짧은 명사 나열로 바꾼다.
/// "이 약은 기침, 가래에 사용합니다." → "기침, 가래"
String efficacyPhrase(String text) {
  var t = text.trim();
  if (t.isEmpty) return '';
  final first = RegExp(r'^.*?(니다\.|\.(?=\s)|$)').firstMatch(t)?.group(0) ?? t;
  t = first
      .replaceFirst(RegExp(r'^이\s*약은\s*'), '')
      .replaceFirst(RegExp(r'\s*(에|의)?\s*(사용|복용|쓰|투여)(합|됩|하십|하게 됩)니다\.?\s*$'), '')
      .replaceFirst(RegExp(r'\s*(에|의)?\s*씁니다\.?\s*$'), '')
      .replaceFirst(RegExp(r'[.\s]+$'), '')
      .trim();
  if (t.length > 90) t = '${t.substring(0, 90)}…';
  return t;
}
