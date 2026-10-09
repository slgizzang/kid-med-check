/// 식약처 조회 결과를 휴대폰 임시 저장 폴더에 파일로 보관한다.
/// (설정 저장소에 넣으면 앱을 켤 때마다 전부 읽어 들여 시작이 멈출 만큼 커질 수 있다)
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class FileCache {
  static Future<Directory?>? _dir;

  /// 보관 폴더 (못 쓰면 null — 그때는 보관 없이 매번 조회)
  static Future<Directory?> _folder() => _dir ??= () async {
        try {
          final base = await getApplicationCacheDirectory();
          final d = Directory('${base.path}/api1');
          if (!await d.exists()) await d.create(recursive: true);
          return d;
        } catch (_) {
          return null;
        }
      }();

  /// 키 → 파일 이름 (32비트 해시 두 개 + 길이)
  static String _name(String key) {
    var a = 0x811c9dc5, b = 0x12345;
    for (final c in utf8.encode(key)) {
      a = ((a ^ c) * 0x01000193) & 0xFFFFFFFF;
      b = ((b * 31) + c) & 0xFFFFFFFF;
    }
    return '${a.toRadixString(16)}${b.toRadixString(16)}${key.length}.json';
  }

  static Future<String?> read(String key, Duration ttl) async {
    try {
      final dir = await _folder();
      if (dir == null) return null;
      final f = File('${dir.path}/${_name(key)}');
      if (!await f.exists()) return null;
      final age = DateTime.now().difference(await f.lastModified());
      if (age > ttl) {
        await f.delete();
        return null;
      }
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, String value) async {
    try {
      final dir = await _folder();
      if (dir == null) return;
      final f = File('${dir.path}/${_name(key)}');
      await f.writeAsString(value, flush: false);
    } catch (_) {}
  }

  /// 기간이 지난 파일을 지우고, 전체가 너무 크면 오래된 것부터 지운다.
  static Future<void> prune(Duration ttl, {int maxBytes = 40 * 1024 * 1024}) async {
    try {
      final files = <(File, DateTime, int)>[];
      final dir = await _folder();
      if (dir == null) return;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final st = await e.stat();
        files.add((e, st.modified, st.size));
      }
      final now = DateTime.now();
      files.sort((a, b) => b.$2.compareTo(a.$2));
      var total = 0;
      for (final (f, t, size) in files) {
        total += size;
        if (now.difference(t) > ttl || total > maxBytes) await f.delete();
      }
    } catch (_) {}
  }
}
