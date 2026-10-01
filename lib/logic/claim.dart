/// 실손보험 청구 준비: 약국 영수증·처방전 사진에서 읽은 글자로 날짜·약국·본인부담금을 찾는다.
/// 값은 참고용이고, 실제 청구는 보험사 앱이나 실손24에서 한다.
library;

class RecordPhoto {
  RecordPhoto({required this.path, this.text = '', required this.at});
  final String path;

  /// 사진에서 읽은 글자 (OCR)
  final String text;
  final DateTime at;

  Map<String, dynamic> toJson() => {'p': path, 't': text, 'at': at.toIso8601String()};

  factory RecordPhoto.fromJson(Map<String, dynamic> j) => RecordPhoto(
        path: '${j['p']}',
        text: '${j['t'] ?? ''}',
        at: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
      );
}

class ClaimInfo {
  ClaimInfo({this.date, this.pharmacy, this.amount});
  final DateTime? date;
  final String? pharmacy;

  /// 본인부담금(원)
  final int? amount;
}

final _money = RegExp(r'(\d{1,3}(?:,\d{3})+|\d{3,7})\s*원?');

int? _num(String s) => int.tryParse(s.replaceAll(',', ''));

ClaimInfo parseReceipt(String text) {
  final lines = text.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).toList();

  // 본인부담금: 우선순위 높은 표현이 있는 줄(또는 바로 다음 줄)의 금액
  int? amount;
  const keys = ['본인부담금', '본인부담', '총수납금액', '수납금액', '영수금액', '납부할금액', '받은금액', '합계'];
  outer:
  for (final k in keys) {
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].replaceAll(' ', '').contains(k)) continue;
      for (final l in [lines[i], if (i + 1 < lines.length) lines[i + 1]]) {
        final ms = _money.allMatches(l.replaceAll(' ', '')).map((m) => _num(m.group(1)!)).whereType<int>()
            .where((v) => v >= 100 && v <= 5000000)
            .toList();
        if (ms.isNotEmpty) {
          amount = ms.last;
          break outer;
        }
      }
    }
  }

  final pharmacy = RegExp(r'([가-힣A-Za-z0-9]{2,20}약국)').firstMatch(text)?.group(1);

  DateTime? date;
  final m = RegExp(r'(20\d{2})\s*[-./년]\s*(\d{1,2})\s*[-./월]\s*(\d{1,2})').firstMatch(text);
  if (m != null) {
    final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
    if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) date = DateTime(y, mo, d);
  }
  return ClaimInfo(date: date, pharmacy: pharmacy, amount: amount);
}

/// 여러 사진의 결과를 합친다 (먼저 찾은 값 우선)
ClaimInfo mergeClaims(Iterable<ClaimInfo> list) {
  DateTime? date;
  String? pharmacy;
  int? amount;
  for (final c in list) {
    date ??= c.date;
    pharmacy ??= c.pharmacy;
    amount ??= c.amount;
  }
  return ClaimInfo(date: date, pharmacy: pharmacy, amount: amount);
}

String formatWon(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '$b원';
}
