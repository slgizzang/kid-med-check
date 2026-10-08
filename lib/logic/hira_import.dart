/// 건강보험심사평가원 '내가 먹는 약 한눈에'에서 내려받은 투약이력 엑셀을
/// 날짜·병원별 처방 기록으로 바꾼다. 모든 처리는 휴대폰 안에서만 한다.
library;

import 'dart:typed_data';

import 'dose.dart';
import 'models.dart';
import 'office_decrypt.dart';
import 'xlsx_reader.dart';

const kHiraServiceName = '건강보험심사평가원 \'내가 먹는 약 한눈에\'';
const kHiraUrl = 'https://www.hira.or.kr/rb/dur/form.do?pgmid=HIRAA050300000100';

/// 한 번의 처방(같은 날짜·같은 병원)
class ImportedVisit {
  ImportedVisit(
      {required this.date,
      required this.place,
      required this.drugs,
      this.hospital = '',
      this.pharmacy = ''});

  final DateTime date;
  final String place;
  final List<String> drugs;

  /// 처방한 병·의원, 조제한 약국 (실손보험 병원비·약값 청구용). 파일에 없으면 빈 문자열.
  String hospital;
  String pharmacy;

  /// 약을 병원에서 바로 받음 (조제기관 = 처방기관)
  bool inHouse = false;

  /// 약 이름 → 처방 용량 (1회 투약량·1일 투여횟수·총 투약일수)
  final Map<String, DoseInfo> doses = {};

  /// 약 이름 → 심평원 '안전성 서한' 칸 내용 (서한이 나온 약만)
  final Map<String, String> safetyLetters = {};

  /// 다시 불러와도 같은 기록을 또 만들지 않기 위한 키
  String get key =>
      'hira|${date.year}-${date.month}-${date.day}|${place.replaceAll(RegExp(r'\s'), '')}';

  String get title =>
      place.isEmpty ? MedRecord.defaultTitle(date) : '${date.month}월 ${date.day}일 $place';
}

class HiraImportResult {
  HiraImportResult(this.visits, {this.passwordOwner});
  final List<ImportedVisit> visits;

  /// 자동으로 연 경우 누구의 생년월일로 열었는지
  final String? passwordOwner;
}

class HiraImport {
  /// 생년월일로 만들 수 있는 비밀번호 후보 (8자리, 6자리)
  static List<String> passwordsFor(DateTime birth) {
    final y = birth.year.toString().padLeft(4, '0');
    final m = birth.month.toString().padLeft(2, '0');
    final d = birth.day.toString().padLeft(2, '0');
    return ['$y$m$d', '${y.substring(2)}$m$d'];
  }

  /// 파일을 열어 방문 목록으로. [people]은 생년월일 사용에 동의한 복용자들(이름, 생년월일).
  /// 자동으로 못 열면 [manualPassword]가 필요하다는 예외(wrongPassword)를 던진다.
  /// 별도 스레드(compute)용 진입점. 화면 객체를 붙잡지 않도록 값만 받는다.
  static HiraImportResult openArgs((Uint8List, List<(String, DateTime)>, String?) a) =>
      open(a.$1, people: a.$2, manualPassword: a.$3);

  static HiraImportResult open(
    Uint8List bytes, {
    List<(String, DateTime)> people = const [],
    String? manualPassword,
  }) {
    final kind = OfficeDecrypt.kindOf(bytes);
    switch (kind) {
      case OfficeKind.plainXlsx:
        return HiraImportResult(parseRows(XlsxReader.readRows(bytes)));
      case OfficeKind.legacyXls:
        throw OfficeFileException('예전 엑셀 형식(.xls)은 아직 읽지 못해요. .xlsx로 내려받아 주세요.');
      case OfficeKind.unknown:
        throw OfficeFileException('엑셀 파일이 아니에요. 심평원에서 내려받은 엑셀 파일을 골라주세요.');
      case OfficeKind.encryptedXlsx:
        break;
    }
    if (manualPassword != null && manualPassword.trim().isNotEmpty) {
      final zip = OfficeDecrypt.decryptXlsx(bytes, manualPassword.trim());
      return HiraImportResult(parseRows(XlsxReader.readRows(zip)));
    }
    for (final (name, birth) in people) {
      for (final pw in passwordsFor(birth)) {
        try {
          final zip = OfficeDecrypt.decryptXlsx(bytes, pw);
          return HiraImportResult(parseRows(XlsxReader.readRows(zip)), passwordOwner: name);
        } on OfficeFileException catch (e) {
          if (!e.wrongPassword) rethrow;
        }
      }
    }
    throw OfficeFileException('비밀번호를 입력해주세요.', wrongPassword: true);
  }

  static const _nameKeys = ['제품명', '약품명', '의약품명', '품명', '약 이름', '약이름'];
  static const _dateKeys = ['조제일', '처방일', '진료일', '투약일자', '일자', '날짜'];
  static const _clinicKeys = ['병·의원', '병의원', '병원', '의원', '처방기관', '요양기관', '기관'];
  /// 심평원 투약이력은 약국을 '조제기관'으로 표시한다
  static const _pharmKeys = ['약국', '조제기관'];
  static const _perDoseKeys = ['1회투약량', '1회투여량', '1회량'];
  static const _timesKeys = ['1일투여횟수', '1일투약횟수', '투여횟수', '투약횟수'];
  static const _daysKeys = ['총투약일수', '총투여일수', '투약일수', '투여일수'];
  static const _unitKeys = ['단위'];
  static const _letterKeys = ['안전성서한', '안전성 서한'];

  /// '안전성 서한' 칸이 서한 있음을 뜻하는지 ("Y", "O", 서한 제목 등). 빈칸·N·없음은 아님.
  static String? safetyLetterOf(String cell) {
    final t = cell.trim();
    if (t.isEmpty) return null;
    if (RegExp(r'^(n|no|x|-|없음|해당\s*없음|0|false)$', caseSensitive: false).hasMatch(t)) return null;
    return t;
  }

  static int _findCol(List<String> header, List<String> keys, {Set<int> skip = const {}}) {
    for (final k in keys) {
      for (var i = 0; i < header.length; i++) {
        if (skip.contains(i)) continue;
        if (header[i].replaceAll(RegExp(r'\s'), '').contains(k.replaceAll(' ', ''))) return i;
      }
    }
    return -1;
  }

  /// 표에서 머리글 줄을 찾아 날짜·병원·약 이름 열을 읽는다.
  static List<ImportedVisit> parseRows(List<List<String>> rows) {
    var h = -1;
    var nameCol = -1, dateCol = -1;
    for (var i = 0; i < rows.length && i < 40; i++) {
      final n = _findCol(rows[i], _nameKeys);
      final d = _findCol(rows[i], _dateKeys, skip: {n});
      if (n >= 0 && d >= 0) {
        h = i;
        nameCol = n;
        dateCol = d;
        break;
      }
    }
    if (h < 0) {
      throw OfficeFileException('투약이력 표를 찾지 못했어요. 심평원에서 내려받은 파일이 맞는지 확인해주세요.');
    }
    final header = rows[h];
    final pharmCol = _findCol(header, _pharmKeys, skip: {nameCol, dateCol});
    final clinicCol = _findCol(header, _clinicKeys, skip: {nameCol, dateCol, pharmCol});
    final placeCol = clinicCol >= 0 ? clinicCol : pharmCol;
    final used = {nameCol, dateCol, pharmCol, clinicCol};
    final perDoseCol = _findCol(header, _perDoseKeys, skip: used);
    final timesCol = _findCol(header, _timesKeys, skip: {...used, perDoseCol});
    final daysCol = _findCol(header, _daysKeys, skip: {...used, perDoseCol, timesCol});
    final unitCol = _findCol(header, _unitKeys, skip: {...used, perDoseCol, timesCol, daysCol});
    final letterCol =
        _findCol(header, _letterKeys, skip: {...used, perDoseCol, timesCol, daysCol, unitCol});

    final byKey = <String, ImportedVisit>{};
    DateTime? lastDate;
    var lastPlace = '';
    for (final r in rows.skip(h + 1)) {
      String cell(int c) => c >= 0 && c < r.length ? r[c].trim() : '';
      final rawName = cell(nameCol);
      if (rawName.isEmpty) continue;
      // 병합된 칸(같은 날짜가 첫 줄에만 있는 경우)은 윗줄 값을 이어 쓴다
      final date = parseDate(cell(dateCol)) ?? lastDate;
      if (date == null) continue;
      final placeCell = cell(placeCol);
      final place = placeCell.isNotEmpty
          ? placeCell
          : (cell(dateCol).isEmpty ? lastPlace : '');
      lastDate = date;
      lastPlace = place;
      final name = cleanDrugName(rawName);
      if (name.length < 2) continue;
      final v = ImportedVisit(date: date, place: place, drugs: []);
      final visit = byKey.putIfAbsent(v.key, () => v);
      if (visit.hospital.isEmpty && clinicCol >= 0) visit.hospital = cell(clinicCol);
      if (visit.pharmacy.isEmpty && !visit.inHouse && pharmCol >= 0) {
        final ph = cell(pharmCol);
        if (isInHouse(cell(clinicCol), ph)) {
          visit.inHouse = true;
        } else {
          visit.pharmacy = ph;
        }
      }
      if (!visit.drugs.contains(name)) visit.drugs.add(name);
      final dose = DoseInfo.parse(
          unit: cell(unitCol), perDose: cell(perDoseCol), times: cell(timesCol), days: cell(daysCol));
      final letter = safetyLetterOf(cell(letterCol));
      if (letter != null) visit.safetyLetters[name] = letter;
      final had = visit.doses[name];
      // 같은 약이 두 줄이면 더 긴 투약일수를 쓴다
      if (dose != null && (had == null || (dose.days ?? 0) > (had.days ?? 0))) {
        visit.doses[name] = dose;
      }
    }
    return byKey.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  /// 조제기관이 처방기관과 같거나 약국이 아니면 병원에서 약을 받은 것 (원내 조제)
  static bool isInHouse(String clinic, String dispenser) {
    String n(String s) => s.replaceAll(RegExp(r'\s'), '');
    final d = n(dispenser);
    if (d.isEmpty) return false;
    if (n(clinic).isNotEmpty && d == n(clinic)) return true;
    return !d.contains('약국');
  }

  /// "싱귤레어세립4밀리그램(몬테루카스트나트륨)" → "싱귤레어세립4밀리그램"
  static String cleanDrugName(String raw) {
    var s = raw.replaceAll(RegExp(r'\s+'), '');
    final cut = s.replaceFirst(RegExp(r'[(\[（].*$'), '');
    if (cut.length >= 2) s = cut;
    return s;
  }

  /// "2026-03-12", "2026.03.12", "2026/3/12", "20260312", 엑셀 날짜 숫자(46093)
  static DateTime? parseDate(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    var m = RegExp(r'^(\d{4})\s*[-./년]\s*(\d{1,2})\s*[-./월]\s*(\d{1,2})').firstMatch(t);
    if (m != null) return _ymd(m.group(1)!, m.group(2)!, m.group(3)!);
    m = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(t);
    if (m != null) return _ymd(m.group(1)!, m.group(2)!, m.group(3)!);
    final n = double.tryParse(t);
    if (n != null && n > 30000 && n < 80000) {
      final d = DateTime(1899, 12, 30).add(Duration(days: n.floor()));
      return DateTime(d.year, d.month, d.day);
    }
    return null;
  }

  static DateTime? _ymd(String y, String m, String d) {
    final yy = int.parse(y), mm = int.parse(m), dd = int.parse(d);
    if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return null;
    return DateTime(yy, mm, dd);
  }
}
