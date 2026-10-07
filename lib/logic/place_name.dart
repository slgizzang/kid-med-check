/// 심평원·병원 정보의 공식 이름을 네이버 지도에서 찾을 수 있는 이름으로 바꾼다.
/// 예: "재단법인아산사회복지재단서울아산병원" → "서울아산병원"
///     "사회복지법인삼성생명공익재단삼성서울병원" → "삼성서울병원"
///     "학교법인가톨릭학원가톨릭대학교서울성모병원" → "가톨릭대학교서울성모병원"
library;

final _legal = RegExp(r'(재단법인|사단법인|의료법인|학교법인|사회복지법인|특수법인|社團|財團)');
final _corp = RegExp(r'\(주\)|\(의\)|\(재\)|\(사\)|\(학\)|주식회사');

/// 법인 이름 끝에 오는 말 (이 뒤부터가 실제 병원·약국 이름)
final _corpEnd = RegExp(r'(사회복지재단|공익재단|의료재단|복지재단|문화재단|재단|학원|의료원법인|법인)');

String searchablePlaceName(String raw) {
  var s = raw.replaceAll(_corp, '').trim();
  if (_legal.hasMatch(s)) {
    s = s.replaceFirst(_legal, '').trim();
    // 법인 이름 끝(…재단, …학원) 다음부터가 기관 이름
    final ends = _corpEnd.allMatches(s).toList();
    for (final m in ends.reversed) {
      final rest = s.substring(m.end).trim();
      if (rest.length >= 2) {
        s = rest;
        break;
      }
    }
  }
  else {
    // "재단법인" 같은 말 없이 법인 이름이 붙은 경우: 성심의료재단강동성심병원 → 강동성심병원
    final m = RegExp(r'^(.{2,}?)(사회복지재단|의료재단|복지재단|공익재단|재단|학원|의료법인)(.{2,})$')
        .firstMatch(s);
    if (m != null && RegExp(r'(병원|의원|센터|클리닉|약국|의료원)$').hasMatch(m.group(3)!)) {
      s = m.group(3)!;
    }
  }
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
