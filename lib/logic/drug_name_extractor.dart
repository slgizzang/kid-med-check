/// 처방전·약봉지 OCR 텍스트에서 약 이름 후보를 뽑는다.
/// 완벽하지 않으므로 화면에서 사용자가 반드시 확인·수정하게 한다.
library;

class DrugNameExtractor {
  /// 약 이름 끝에 붙는 제형
  static const _forms = [
    '연질캡슐', '경질캡슐', '서방캡슐', '서방정', '장용정', '필름코팅정', '츄어블정',
    '구강붕해정', '발포정', '분산정', '건조시럽', '현탁시럽', '현탁액', '시럽',
    '엘릭서', '드롭스', '트로키', '츄정', '캡슐', '과립', '세립', '점안액', '점비액',
    '좌제', '좌약', '패취', '패치', '크림', '연고', '로션', '흡입액', '산', '정', '액', '겔',
  ];

  /// 제형 앞에 붙는 수식어 (이것만 단독으로는 약 이름이 아님)
  static const _modifiers = [
    '현탁용', '시럽용', '필름코팅', '구강붕해', '연질', '경질', '서방', '장용', '츄어블',
    '발포', '분산', '건조', '현탁', '분말',
  ];

  static final String _formAlt = _forms.join('|');
  static final String _modAlt = _modifiers.join('|');

  static final RegExp _pattern = RegExp(
    r'(?<![가-힣A-Za-z0-9])([가-힣A-Za-z][가-힣A-Za-z0-9\-]*?(?:' +
        _formAlt +
        r'))(?=[0-9\s(\[,/.·:]|$)',
  );

  /// "현탁액", "건조시럽 5mL"처럼 제형만 있는 토큰
  static final RegExp _formOnlyToken =
      RegExp('^(?:$_modAlt)*(?:$_formAlt)(?=[0-9(\\[,/.·:]|\$)');

  /// 이름 전체가 제형뿐인 경우 (예: "현탁액", "건조시럽")
  static final RegExp _formOnlyName = RegExp('^(?:$_modAlt)*(?:$_formAlt)\$');

  static final RegExp _endsWithForm = RegExp('(?:$_formAlt)\$');
  static final RegExp _endsWithLetter = RegExp(r'[가-힣A-Za-z]$');

  /// 약 이름이 아닌데 '정/액/산'으로 끝나기 쉬운 단어들
  static const _blockedParts = [
    '처방', '조제', '약국', '병원', '의원', '부담', '금액', '합계', '수납', '영수',
    '복용', '용법', '보험', '번호', '주소', '면허', '발행', '교부', '본인', '기간',
    '일수', '횟수', '투약', '의사', '약사', '환자', '성명', '계산', '조정', '결정',
    '측정', '일정', '지정', '규정', '예정', '확정', '인정', '수정', '설정', '과정',
    '가정', '추정', '특정', '산정', '사정', '감정', '교정', '보정', '적정', '공정',
    '검정', '판정', '총액', '잔액', '차액', '정액', '전액', '생산', '예산', '재산',
    '부산', '울산', '서울', '주의', '보관', '냉장', '실온', '식후', '식전', '아침',
    '점심', '저녁', '취침', '흔들', '복약', '안내', '전화', '주민',
  ];

  /// OCR이 "맥시부펜 현탁액"처럼 이름 중간을 띄우거나 줄을 바꾼 경우,
  /// 제형만 남은 토큰을 앞 단어에 붙인다.
  static bool _canJoin(String prev, String next) {
    if (!_formOnlyToken.hasMatch(next)) return false;
    if (!_endsWithLetter.hasMatch(prev)) return false;
    if (_endsWithForm.hasMatch(prev)) return false;
    if (_formOnlyName.hasMatch(prev)) return false;
    if (_blockedParts.any(prev.contains)) return false;
    return true;
  }

  static final RegExp _lettersOnly = RegExp(r'^[가-힣A-Za-z]{2,}$');

  /// 약 이름 앞부분이 될 수 있는 단어 (글자만, 제형으로 끝나지 않음, 금지어 아님)
  static bool _isNamePart(String t) =>
      _lettersOnly.hasMatch(t) &&
      !_endsWithForm.hasMatch(t) &&
      !_blockedParts.any(t.contains) &&
      !_nonNameWords.contains(t);

  /// 약봉지에 자주 나오지만 약 이름 일부가 아닌 단어
  static const _nonNameWords = {'님', '잘', '및', '또는', '매일', '하루', '약', '먹는', '바르는'};

  static List<String> normalizeLines(String text) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((l) => l.isNotEmpty)
        .map((l) => l.split(' '))
        .toList();

    for (var i = 0; i < lines.length; i++) {
      final toks = lines[i];
      for (var j = 1; j < toks.length; j++) {
        if (_canJoin(toks[j - 1], toks[j])) {
          // "코대원 포르테 시럽"처럼 여러 단어로 끊긴 이름은 앞 단어를 최대 2개 더 붙인다.
          var start = j - 1;
          while (start > 0 &&
              j - start < 3 &&
              _isNamePart(toks[start - 1])) {
            start--;
          }
          final joined = toks.sublist(start, j + 1).join();
          toks.replaceRange(start, j + 1, [joined]);
          j = start;
        }
      }
      // 줄바꿈으로 잘린 경우: 윗줄 마지막 단어 + 이 줄 첫 토큰
      if (i > 0 && toks.isNotEmpty && lines[i - 1].isNotEmpty) {
        final prevLine = lines[i - 1];
        if (_canJoin(prevLine.last, toks.first)) {
          prevLine[prevLine.length - 1] = prevLine.last + toks.first;
          toks.removeAt(0);
        }
      }
    }
    return lines.map((t) => t.join(' ')).where((l) => l.isNotEmpty).toList();
  }

  static List<String> extract(String text) {
    final result = <String>[];
    final seen = <String>{};
    for (final line in normalizeLines(text)) {
      for (final m in _pattern.allMatches(line)) {
        final name = m.group(1)!;
        if (name.length < 3) continue;
        if (_formOnlyName.hasMatch(name)) continue;
        if (_blockedParts.any(name.contains)) continue;
        if (seen.add(name)) result.add(name);
      }
    }
    return result.take(30).toList();
  }

  static final RegExp _trailingForm = RegExp('(?:$_modAlt)*(?:$_formAlt)\$');

  /// 검색 순서: 원래 이름 → 제형을 뗀 이름 (예: "코대원포르테시럽" → "코대원포르테")
  /// OCR이 제형 글자를 틀리게 읽었을 때도 찾을 수 있게 한다.
  static List<String> searchVariants(String name) {
    final out = <String>[name];
    final stem = name.replaceFirst(_trailingForm, '');
    // 너무 짧게 줄이면 엉뚱한 약이 걸리므로 3글자 이상일 때만
    if (stem.length >= 3 && stem != name) out.add(stem);
    return out;
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
