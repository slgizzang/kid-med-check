/// 최소한의 xlsx 읽기: 첫 번째(또는 모든) 시트의 셀 값을 문자열 표로.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class XlsxReader {
  /// 모든 시트의 행을 이어서 돌려준다 (시트 순서대로).
  static List<List<String>> readRows(Uint8List zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    String? text(String name) {
      final f = archive.findFile(name);
      if (f == null) return null;
      return utf8.decode(List<int>.from(f.content as List), allowMalformed: true);
    }

    final shared = <String>[];
    final ss = text('xl/sharedStrings.xml');
    if (ss != null) {
      for (final si in _els(XmlDocument.parse(ss), 'si')) {
        shared.add(_els(si, 't').map((t) => t.innerText).join());
      }
    }

    final sheets = archive.files
        .map((f) => f.name)
        .where((n) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(n))
        .toList()
      ..sort((a, b) => _num(a).compareTo(_num(b)));

    final rows = <List<String>>[];
    for (final s in sheets) {
      final doc = XmlDocument.parse(text(s)!);
      for (final row in _els(doc, 'row')) {
        final cells = <int, String>{};
        var next = 0;
        for (final c in row.childElements.where((e) => e.name.local == 'c')) {
          final ref = c.getAttribute('r');
          final col = ref != null ? _colIndex(ref) : next;
          next = col + 1;
          final t = c.getAttribute('t');
          String v;
          if (t == 'inlineStr') {
            v = _els(c, 't').map((e) => e.innerText).join();
          } else {
            final ve = c.childElements.where((e) => e.name.local == 'v');
            final raw = ve.isEmpty ? '' : ve.first.innerText;
            if (t == 's') {
              final i = int.tryParse(raw);
              v = (i != null && i < shared.length) ? shared[i] : '';
            } else {
              v = raw;
            }
          }
          cells[col] = v.trim();
        }
        if (cells.isEmpty) {
          rows.add(const []);
          continue;
        }
        final maxCol = cells.keys.reduce((a, b) => a > b ? a : b);
        rows.add([for (var i = 0; i <= maxCol; i++) cells[i] ?? '']);
      }
    }
    return rows;
  }

  static Iterable<XmlElement> _els(XmlNode n, String local) =>
      n.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

  static int _num(String path) =>
      int.tryParse(RegExp(r'(\d+)\.xml$').firstMatch(path)?.group(1) ?? '') ?? 0;

  /// "C12" → 2
  static int _colIndex(String ref) {
    var n = 0;
    for (final ch in ref.codeUnits) {
      if (ch >= 65 && ch <= 90) {
        n = n * 26 + (ch - 64);
      } else if (ch >= 97 && ch <= 122) {
        n = n * 26 + (ch - 96);
      } else {
        break;
      }
    }
    return n - 1;
  }
}
