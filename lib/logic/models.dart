import 'allergy.dart';
import 'claim.dart';
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
    this.allergies = const [],
  });

  /// 알레르기가 있는 약물 (계열 이름 또는 약·성분 이름)
  final List<String> allergies;

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
        if (allergies.isNotEmpty) 'allergies': allergies,
      };

  factory ChildProfile.fromJson(Map<String, dynamic> j) => ChildProfile(
        id: '${j['id']}',
        name: '${j['name']}',
        birthDate: DateTime.parse('${j['birth']}'),
        pregnant: j['pregnant'] == true,
        nursing: j['nursing'] == true,
        allergies: (j['allergies'] as List? ?? const []).map((e) => '$e').toList(),
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
    this.importKey,
    this.otc = false,
    this.claimed = false,
    this.hospital = '',
    this.hospitalAddr = '',
    this.pharmacy = '',
    this.pharmacyAddr = '',
    this.hospitalCode = '',
    this.pharmacyCode = '',
    this.hospitalPos,
    this.pharmacyPos,
    this.claimedPharm = false,
    this.inHouse = false,
    List<RecordPhoto>? photos,
    Map<String, String>? safetyLetters,
  })  : drugs = drugs ?? [],
        photos = photos ?? [],
        safetyLetters = safetyLetters ?? {};

  /// 약 이름 → 심평원 투약이력의 '안전성 서한' 표시 (식약처가 안전성 서한을 낸 약)
  final Map<String, String> safetyLetters;


  /// 찍어둔 처방전·약봉지·영수증 사진 (실손보험 청구용)
  final List<RecordPhoto> photos;

  /// 약국에서 직접 산 약(일반의약품)이면 true, 병원 처방이면 false
  bool otc;

  /// 병원비(진료비) 실손보험 청구를 마쳤다고 표시했는지
  bool claimed;

  /// 약값(약국 조제비) 실손보험 청구를 마쳤다고 표시했는지
  bool claimedPharm;

  /// 약을 병원에서 바로 받음(원내 조제) — 약값이 병원비에 포함되어 약국 청구가 따로 없다
  bool inHouse;

  /// 진료받은 병원 이름 (실손보험 청구 때 네이버 지도에서 찾기용). 모르면 빈 문자열.
  String hospital;

  /// 병원 주소 (네이버 지도 검색을 정확하게)
  String hospitalAddr;

  /// 약을 지은 약국 이름·주소
  String pharmacy;
  String pharmacyAddr;

  /// 심평원 요양기관 코드(암호화 ykiho). 실손24 기관과 정확히 맞출 때 쓴다.
  String hospitalCode;
  String pharmacyCode;

  /// 병원·약국 위치 (위도, 경도). 실손24에서 같은 이름 중 바로 그곳을 고를 때 쓴다.
  (double, double)? hospitalPos;
  (double, double)? pharmacyPos;

  static List<double>? _posJson((double, double)? p) => p == null ? null : [p.$1, p.$2];
  static (double, double)? _posOf(dynamic v) =>
      v is List && v.length == 2 && v[0] is num && v[1] is num
          ? ((v[0] as num).toDouble(), (v[1] as num).toDouble())
          : null;

  /// 병원비·약값 청구를 모두 마쳤는지 (약국을 모르면 병원비만 본다)
  bool get fullyClaimed => claimed && (claimedPharm || pharmacy.isEmpty || inHouse);

  /// 심평원 투약이력에서 불러온 기록인지
  bool get imported => importKey != null;

  /// 심평원 투약이력에서 불러온 기록이면 그 키 (중복 방지)
  final String? importKey;

  final String id;
  final String childId;
  String title;
  final DateTime createdAt;
  final List<String> drugs;

  /// 마지막 확인 결과 (없으면 null)
  ResultSnapshot? last;

  static String defaultTitle(DateTime d, {bool otc = false}) =>
      '${d.month}월 ${d.day}일 ${otc ? '약국 구입' : '처방'}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'childId': childId,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'drugs': drugs,
        if (last != null) 'last': last!.toJson(),
        if (importKey != null) 'import': importKey,
        if (otc) 'otc': true,
        if (claimed) 'claimed': true,
        if (hospital.isNotEmpty) 'hospital': hospital,
        if (hospitalAddr.isNotEmpty) 'hospitalAddr': hospitalAddr,
        if (pharmacy.isNotEmpty) 'pharmacy': pharmacy,
        if (pharmacyAddr.isNotEmpty) 'pharmacyAddr': pharmacyAddr,
        if (hospitalCode.isNotEmpty) 'hospitalCode': hospitalCode,
        if (pharmacyCode.isNotEmpty) 'pharmacyCode': pharmacyCode,
        if (hospitalPos != null) 'hospitalPos': _posJson(hospitalPos),
        if (pharmacyPos != null) 'pharmacyPos': _posJson(pharmacyPos),
        if (claimedPharm) 'claimedPharm': true,
        if (inHouse) 'inHouse': true,
        if (photos.isNotEmpty) 'photos': photos.map((p) => p.toJson()).toList(),
        if (safetyLetters.isNotEmpty) 'letters': safetyLetters,
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
        importKey: j['import'] as String?,
        otc: j['otc'] == true,
        claimed: j['claimed'] == true,
        hospital: '${j['hospital'] ?? ''}',
        hospitalAddr: '${j['hospitalAddr'] ?? ''}',
        pharmacy: '${j['pharmacy'] ?? ''}',
        pharmacyAddr: '${j['pharmacyAddr'] ?? ''}',
        hospitalCode: '${j['hospitalCode'] ?? ''}',
        pharmacyCode: '${j['pharmacyCode'] ?? ''}',
        hospitalPos: _posOf(j['hospitalPos']),
        pharmacyPos: _posOf(j['pharmacyPos']),
        claimedPharm: j['claimedPharm'] == true,
        inHouse: j['inHouse'] == true,
        photos: (j['photos'] as List? ?? const [])
            .map((e) => RecordPhoto.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        safetyLetters: {
          for (final e in (j['letters'] as Map? ?? const {}).entries) '${e.key}': '${e.value}',
        },
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

  /// 후보 중 연령금기 목록에 있는 제품명
  Set<String> tabooNames = const {};

  /// 후보별로 복용자에게 해당하는 주의 태그 (예: "연령금기", "임부금기")
  Map<String, List<String>> candidateTags = const {};

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

  /// 복용자 알레르기 약물과 같은 성분·계열
  List<AllergyHit> allergyHits = const [];
  bool get hasAllergy => allergyHits.isNotEmpty;

  bool get hasPreg => pregRows.isNotEmpty;
  bool get hasMix => interactions.isNotEmpty;

  /// 빨간 경고가 필요한지 (연령금기·임부금기·병용금기)
  bool get isDanger => status == CheckStatus.danger || hasPreg || hasMix || hasAllergy;

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

/// 설명서 문장 중 수유부 관련 부분만 한 줄로 요약한다.
/// e약은요는 "…마십시오.이 약을…"처럼 마침표 뒤에 띄어쓰기가 없어 마침표 기준으로 나눈다.
String? nursingSummary(String text) {
  final sentences = text
      .split(RegExp(r'(?<=[.。])(?!\d)'))
      .map((x) => x.trim())
      .where((x) => x.isNotEmpty);
  for (final sen in sentences) {
    if (!sen.contains('수유')) continue;
    if (RegExp(r'수유를?\s*(중단|중지|피)').hasMatch(sen)) {
      return '복용하는 동안에는 수유를 중단하도록 되어 있어요.';
    }
    if (RegExp(r'(복용|투여|사용)하지\s*(마|않)').hasMatch(sen) &&
        !sen.contains('상의')) {
      return '수유부는 복용하지 않도록 되어 있어요.';
    }
    if (sen.contains('상의')) {
      return '수유부는 복용 전에 의사 또는 약사와 상의하도록 되어 있어요.';
    }
    if (sen.length <= 60) return sen;
    return '설명서에 수유부 관련 주의사항이 있어요. 약사에게 확인해주세요.';
  }
  return null;
}
