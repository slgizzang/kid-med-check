/// 처방전·약봉지 OCR 텍스트에서 약 이름 후보를 뽑는다.
/// 완벽하지 않으므로 화면에서 사용자가 반드시 확인·수정하게 한다.
library;

class DrugNameExtractor {
  static const _forms = [
    '연질캡슐', '경질캡슐', '서방캡슐', '서방정', '장용정', '필름코팅정', '츄어블정',
    '구강붕해정', '발포정', '분산정', '건조시럽', '현탁시럽', '현탁액', '시럽',
    '캡슐', '과립', '세립', '점안액', '점비액', '좌제', '좌약', '패취', '패치',
    '크림', '연고', '로션', '흡입액', '산', '정', '액', '겔',
  ];

  static final RegExp _pattern = RegExp(
    r'(?<![가-힣A-Za-z0-9])([가-힣A-Za-z][가-힣A-Za-z0-9\-]*?(?:' +
        _forms.join('|') +
        r'))(?=[0-9\s(\[,/.·:]|$)',
  );

  /// 약 이름이 아닌데 '정/액/산'으로 끝나기 쉬운 단어들
  static const _blockedParts = [
    '처방', '조제', '약국', '병원', '의원', '부담', '금액', '합계', '수납', '영수',
    '복용', '용법', '보험', '번호', '주소', '면허', '발행', '교부', '본인', '기간',
    '일수', '횟수', '투약', '의사', '약사', '환자', '성명', '계산', '조정', '결정',
    '측정', '일정', '지정', '규정', '예정', '확정', '인정', '수정', '설정', '과정',
    '가정', '추정', '특정', '산정', '사정', '감정', '교정', '보정', '적정', '공정',
    '검정', '판정', '총액', '잔액', '차액', '정액', '전액', '생산', '예산', '재산',
    '부산', '울산', '서울', '주의', '보관', '냉장', '실온',
  ];

  static List<String> extract(String text) {
    final result = <String>[];
    final seen = <String>{};
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final compact = line.replaceAll(RegExp(r'\s+'), ' ').trim();
      for (final m in _pattern.allMatches(compact)) {
        final name = m.group(1)!;
        if (name.length < 3) continue;
        if (_blockedParts.any(name.contains)) continue;
        if (seen.add(name)) result.add(name);
      }
    }
    return result.take(30).toList();
  }

  /// 사용자가 직접 입력한 여러 줄/쉼표 구분 텍스트를 이름 목록으로
  static List<String> splitManual(String text) {
    return text
        .split(RegExp(r'[\n,，、;]+'))
        .map((s) => s.replaceAll(RegExp(r'\s+'), '').trim())
        .where((s) => s.length >= 2)
        .toList();
  }

  /// API 검색용으로 용량 표기·괄호 성분명 등을 떼어낸다.
  /// 예: "타이레놀정500밀리그램(아세트아미노펜)" -> "타이레놀정"
  static String toSearchName(String raw) {
    var s = raw.replaceAll(RegExp(r'\s+'), '');
    s = s.replaceAll(RegExp(r'[(\[（].*$'), '');
    final stripped = s.replaceFirst(
        RegExp(r'\d+(?:\.\d+)?(?:밀리그램|마이크로그램|밀리리터|그램|mg|mcg|ml|g|㎎|㎖|%).*$',
            caseSensitive: false),
        '');
    if (stripped.length >= 2) s = stripped;
    return s;
  }
}
