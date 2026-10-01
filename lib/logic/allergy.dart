/// 복용자가 입력한 알레르기 약물과 같은 성분·같은 계열이 처방약에 들어 있는지 확인한다.
/// 같은 계열 대조만 하고, 다른 계열 간 교차 반응은 추정하지 않는다.
library;

/// 자주 쓰는 약물 계열 → 그 계열 성분 (한글·영문)
const kAllergyClasses = <String, List<String>>{
  '페니실린계': [
    '페니실린', '아목시실린', '암피실린', '클록사실린', '피페라실린', '설타미실린', '바캄피실린', '나프실린',
    'penicillin', 'amoxicillin', 'ampicillin', 'cloxacillin', 'piperacillin', 'sultamicillin',
  ],
  '세팔로스포린계': [
    '세파클러', '세팔렉신', '세파드록실', '세프디니르', '세프포독심', '세푸록심', '세프트리악손', '세픽심',
    '세프디토렌', '세프카펜', '세프프로질', '세파졸린', '세포탁심', '세프타지딤',
    'cefaclor', 'cephalexin', 'cefadroxil', 'cefdinir', 'cefpodoxime', 'cefuroxime', 'ceftriaxone',
    'cefixime', 'cefditoren', 'cefcapene', 'cefprozil', 'cefazolin',
  ],
  '마크로라이드계': [
    '클래리트로마이신', '클라리트로마이신', '아지트로마이신', '에리트로마이신', '록시트로마이신',
    'clarithromycin', 'azithromycin', 'erythromycin', 'roxithromycin',
  ],
  '설파제': ['설파메톡사졸', '설파', 'sulfamethoxazole', 'sulfa'],
  '퀴놀론계': [
    '시프로플록사신', '레보플록사신', '오플록사신', '목시플록사신',
    'ciprofloxacin', 'levofloxacin', 'ofloxacin', 'moxifloxacin',
  ],
  '소염진통제(NSAIDs)': [
    '이부프로펜', '덱시부프로펜', '나프록센', '아스피린', '아세틸살리실산', '아세클로페낙', '디클로페낙',
    '메페남산', '록소프로펜', '케토프로펜', '펠루비프로펜', '잘토프로펜',
    'ibuprofen', 'dexibuprofen', 'naproxen', 'aspirin', 'acetylsalicylic', 'aceclofenac',
    'diclofenac', 'mefenamic', 'loxoprofen', 'ketoprofen',
  ],
  '아세트아미노펜': ['아세트아미노펜', '파라세타몰', 'acetaminophen', 'paracetamol'],
};

/// 입력 화면에서 바로 고를 수 있는 계열
List<String> get kAllergyQuickPicks => kAllergyClasses.keys.toList();

String _n(String s) => s.replaceAll(RegExp(r'[\s·.,()\-]'), '').toLowerCase();

/// 알레르기 하나를 대조할 단어들로 펼친다.
/// 계열 이름이면 그 계열 성분 전체, 아니면 입력한 약 이름·성분 그대로.
List<String> expandAllergy(String allergy) {
  final a = _n(allergy);
  if (a.isEmpty) return const [];
  const aliases = {'세파': '세팔로스포린계', '세프': '세팔로스포린계', '마크로': '마크로라이드계', '설폰': '설파제'};
  for (final e in aliases.entries) {
    if (a.startsWith(e.key) && (a.endsWith('계') || a.length <= 3)) return kAllergyClasses[e.value]!;
  }
  for (final e in kAllergyClasses.entries) {
    final key = _n(e.key);
    final base = key.replaceAll(RegExp(r'(계|제|nsaids)$'), '');
    if (a == key || (base.length >= 2 && a.contains(base)) || (key.contains(a) && a.length >= 3)) {
      return e.value;
    }
  }
  // 성분 이름을 직접 쓴 경우 그 성분이 속한 계열을 함께 대조하지는 않는다 (같은 성분만).
  // 염·수화물 표기는 떼고 대조한다 (예: 아목시실린수화물 → 아목시실린)
  var base = allergy.replaceAll(RegExp(r'\s'), '');
  final salt = RegExp(r'(이수화물|삼수화물|수화물|무수물|나트륨|칼륨|칼슘|염산염|황산염|말레산염|타르타르산염|브롬화수소산염)$');
  while (salt.hasMatch(base) && base.length > 3) {
    base = base.replaceFirst(salt, '');
  }
  return {allergy, base}.toList();
}

class AllergyHit {
  const AllergyHit(this.allergy, this.matched);

  /// 복용자가 입력한 알레르기 (예: "페니실린계")
  final String allergy;

  /// 처방약에서 찾은 성분 (예: "아목시실린")
  final String matched;
}

/// 약 이름·성분·분류에서 알레르기 약물과 같은 것을 찾는다.
List<AllergyHit> allergyHits(
    List<String> allergies, String name, String ingredient, String cls) {
  final hay = _n('$name $ingredient');
  final hits = <AllergyHit>[];
  for (final a in allergies) {
    for (final term in expandAllergy(a)) {
      final t = _n(term);
      if (t.length < 2) continue;
      if (hay.contains(t)) {
        hits.add(AllergyHit(a, term));
        break;
      }
    }
  }
  return hits;
}
