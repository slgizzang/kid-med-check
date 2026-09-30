/// 식약처 DUR 금기 사유 문구를 읽기 쉽게 다듬는다.
/// 원문은 마침표 없이 이어지고 전문 용어(랫트·태자 등)가 많다.
/// 뜻은 바꾸지 않고 문장 나누기와 용어 풀이만 한다.
library;

const _terms = <String, String>{
  '랫트': '쥐',
  '랫드': '쥐',
  '래트': '쥐',
  '마우스': '생쥐',
  '태자': '태아',
  '최기형성': '기형 유발',
  '기형발생': '기형 발생',
};

/// 문장이 끝나는 말 (뒤에 공백과 다른 말이 이어지면 거기서 끊는다)
const _enders = [
  '미확립', '않음', '않았음', '보고', '보고됨', '있음', '없음', '우려', '확인됨', '관찰됨',
];

final _animal = RegExp(r'(쥐|토끼|원숭이|햄스터|동물)');

String friendlyTaboo(String raw) {
  var s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return s;
  _terms.forEach((k, v) => s = s.replaceAll(k, v));

  // 끝맺는 말 뒤에서 문장을 나눈다
  final alt = _enders.map(RegExp.escape).join('|');
  s = s.replaceAllMapped(
      RegExp('($alt)(?=\\s+[^\\s.,)])'), (m) => '${m.group(1)}.');

  final sentences = s
      .split(RegExp(r'(?<=[.])\s+'))
      .map((x) => x.trim())
      .where((x) => x.isNotEmpty)
      .map((x) {
    var t = x;
    // 동물 실험 결과임을 밝힌다
    if (_animal.hasMatch(t) && !t.contains('동물')) t = '(동물실험) $t';
    if (!RegExp(r'[.!?)]$').hasMatch(t)) t = '$t.';
    return t;
  }).toList();
  return sentences.join(' ');
}
