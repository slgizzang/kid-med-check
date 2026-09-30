import 'dur_api.dart';
import 'label_age.dart';

class ChildProfile {
  ChildProfile({required this.id, required this.name, required this.birthDate});

  final String id;
  final String name;
  final DateTime birthDate;

  int ageInMonths([DateTime? now]) => monthsBetween(birthDate, now ?? DateTime.now());

  String get ageLabel => formatAge(ageInMonths());

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'birth': birthDate.toIso8601String()};

  factory ChildProfile.fromJson(Map<String, dynamic> j) => ChildProfile(
        id: '${j['id']}',
        name: '${j['name']}',
        birthDate: DateTime.parse('${j['birth']}'),
      );
}

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

enum CheckStatus { loading, danger, labelCaution, unknown, listedOk, notListed, error }

class DrugCheck {
  DrugCheck(this.query);

  final String query;
  CheckStatus status = CheckStatus.loading;
  List<TabooRow> rows = const [];
  String? error;

  /// 실제로 결과를 찾은 검색어 (원래 이름으로 못 찾아 줄여서 찾은 경우 다름)
  String? matchedQuery;

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
