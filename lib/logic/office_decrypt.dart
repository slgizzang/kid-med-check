/// 비밀번호가 걸린 엑셀(.xlsx) 파일을 휴대폰 안에서 푼다.
/// 암호화된 xlsx는 OLE(CFB) 컨테이너 안에 EncryptionInfo·EncryptedPackage 스트림으로 들어 있다.
/// (MS-OFFCRYPTO: Agile·Standard 암호화 지원)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class OfficeFileException implements Exception {
  OfficeFileException(this.message, {this.wrongPassword = false});
  final String message;
  final bool wrongPassword;
  @override
  String toString() => message;
}

enum OfficeKind { plainXlsx, encryptedXlsx, legacyXls, unknown }

class OfficeDecrypt {
  static const _cfbMagic = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];

  static OfficeKind kindOf(Uint8List data) {
    if (data.length > 4 && data[0] == 0x50 && data[1] == 0x4B) return OfficeKind.plainXlsx;
    if (data.length < 512) return OfficeKind.unknown;
    for (var i = 0; i < 8; i++) {
      if (data[i] != _cfbMagic[i]) return OfficeKind.unknown;
    }
    final cfb = _Cfb(data);
    if (cfb.has('EncryptionInfo') && cfb.has('EncryptedPackage')) {
      return OfficeKind.encryptedXlsx;
    }
    if (cfb.has('Workbook') || cfb.has('Book')) return OfficeKind.legacyXls;
    return OfficeKind.unknown;
  }

  /// 암호화된 xlsx를 풀어 원래 xlsx(zip) 바이트를 돌려준다.
  /// 비밀번호가 틀리면 wrongPassword=true 예외.
  static Uint8List decryptXlsx(Uint8List data, String password) {
    final cfb = _Cfb(data);
    final info = cfb.stream('EncryptionInfo');
    final pkg = cfb.stream('EncryptedPackage');
    if (info == null || pkg == null) {
      throw OfficeFileException('암호화된 엑셀 파일이 아니에요.');
    }
    final major = info[0] | (info[1] << 8);
    final minor = info[2] | (info[3] << 8);
    Uint8List out;
    if (major == 4 && minor == 4) {
      out = _agile(info, pkg, password);
    } else if ((major == 3 || major == 4) && minor == 2) {
      out = _standard(info, pkg, password);
    } else {
      throw OfficeFileException('지원하지 않는 암호화 방식이에요 ($major.$minor).');
    }
    if (out.length < 4 || out[0] != 0x50 || out[1] != 0x4B) {
      throw OfficeFileException('비밀번호가 맞지 않아요.', wrongPassword: true);
    }
    return out;
  }

  // ---------------- Agile ----------------

  static const _blockKeyEncryptedKey = [0x14, 0x6e, 0x0b, 0xe7, 0xab, 0xac, 0xd0, 0xd6];

  static Uint8List _agile(Uint8List info, Uint8List pkg, String password) {
    final xml = utf8.decode(info.sublist(8), allowMalformed: true);
    final keyData = RegExp(r'<(?:\w+:)?keyData\b([^>]*)>').firstMatch(xml)?.group(1);
    final encKey = RegExp(r'<(?:\w+:)?encryptedKey\b([^>]*)>').firstMatch(xml)?.group(1);
    if (keyData == null || encKey == null) {
      throw OfficeFileException('암호화 정보를 읽지 못했어요.');
    }
    String attr(String s, String name) {
      final m = RegExp('\\b$name="([^"]*)"').firstMatch(s);
      if (m == null) throw OfficeFileException('암호화 정보($name)를 읽지 못했어요.');
      return m.group(1)!;
    }

    final hashName = attr(encKey, 'hashAlgorithm');
    final salt = base64.decode(attr(encKey, 'saltValue'));
    final spin = int.parse(attr(encKey, 'spinCount'));
    final keyBytes = int.parse(attr(encKey, 'keyBits')) ~/ 8;
    final encKeyValue = base64.decode(attr(encKey, 'encryptedKeyValue'));

    var h = _hash(hashName, _cat([salt, _utf16le(password)]));
    for (var i = 0; i < spin; i++) {
      h = _hash(hashName, _cat([_u32(i), h]));
    }
    var k = _hash(hashName, _cat([h, Uint8List.fromList(_blockKeyEncryptedKey)]));
    k = _fit(k, keyBytes);
    final secret = _aesCbc(k, Uint8List.fromList(salt), Uint8List.fromList(encKeyValue))
        .sublist(0, keyBytes);

    final kdSalt = base64.decode(attr(keyData, 'saltValue'));
    final kdHash = attr(keyData, 'hashAlgorithm');
    final blockSize = int.parse(attr(keyData, 'blockSize'));
    final total = _u64(pkg, 0);
    final body = pkg.sublist(8);
    final out = BytesBuilder(copy: false);
    for (var off = 0, seg = 0; off < body.length; off += 4096, seg++) {
      var end = off + 4096;
      if (end > body.length) end = body.length;
      var chunk = body.sublist(off, end);
      final rem = chunk.length % 16;
      if (rem != 0) chunk = Uint8List.fromList([...chunk, ...List.filled(16 - rem, 0)]);
      final iv = _hash(kdHash, _cat([Uint8List.fromList(kdSalt), _u32(seg)]))
          .sublist(0, blockSize);
      out.add(_aesCbc(secret, iv, chunk));
    }
    final all = out.takeBytes();
    return all.length > total ? all.sublist(0, total) : all;
  }

  // ---------------- Standard ----------------

  static Uint8List _standard(Uint8List info, Uint8List pkg, String password) {
    final bd = ByteData.sublistView(info);
    final headerSize = bd.getUint32(8, Endian.little);
    final h0 = 12;
    final keyBits = bd.getUint32(h0 + 16, Endian.little);
    final v0 = h0 + headerSize;
    final saltSize = bd.getUint32(v0, Endian.little);
    final salt = info.sublist(v0 + 4, v0 + 4 + saltSize);

    var h = _hash('SHA1', _cat([salt, _utf16le(password)]));
    for (var i = 0; i < 50000; i++) {
      h = _hash('SHA1', _cat([_u32(i), h]));
    }
    h = _hash('SHA1', _cat([h, _u32(0)]));
    final buf1 = Uint8List(64)..fillRange(0, 64, 0x36);
    final buf2 = Uint8List(64)..fillRange(0, 64, 0x5c);
    for (var i = 0; i < h.length; i++) {
      buf1[i] ^= h[i];
      buf2[i] ^= h[i];
    }
    final x = _cat([_hash('SHA1', buf1), _hash('SHA1', buf2)]);
    final key = x.sublist(0, keyBits ~/ 8);

    final total = _u64(pkg, 0);
    var body = pkg.sublist(8);
    final rem = body.length % 16;
    if (rem != 0) body = Uint8List.fromList([...body, ...List.filled(16 - rem, 0)]);
    final aes = AESEngine()..init(false, KeyParameter(key));
    final out = Uint8List(body.length);
    for (var off = 0; off < body.length; off += 16) {
      aes.processBlock(body, off, out, off);
    }
    return out.length > total ? out.sublist(0, total) : out;
  }

  // ---------------- helpers ----------------

  static Uint8List _hash(String name, Uint8List data) {
    final Digest d = switch (name.toUpperCase().replaceAll('-', '')) {
      'SHA512' => SHA512Digest(),
      'SHA384' => SHA384Digest(),
      'SHA256' => SHA256Digest(),
      'SHA1' => SHA1Digest(),
      _ => throw OfficeFileException('지원하지 않는 해시 방식이에요 ($name).'),
    };
    return d.process(data);
  }

  static Uint8List _aesCbc(Uint8List key, Uint8List iv, Uint8List data) {
    final c = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(key), iv));
    final out = Uint8List(data.length);
    for (var off = 0; off + 16 <= data.length; off += 16) {
      c.processBlock(data, off, out, off);
    }
    return out;
  }

  static Uint8List _fit(Uint8List k, int len) {
    if (k.length >= len) return k.sublist(0, len);
    return Uint8List.fromList([...k, ...List.filled(len - k.length, 0x36)]);
  }

  static Uint8List _utf16le(String s) {
    final out = Uint8List(s.length * 2);
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      out[i * 2] = c & 0xff;
      out[i * 2 + 1] = c >> 8;
    }
    return out;
  }

  static Uint8List _u32(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

  static int _u64(Uint8List b, int off) {
    final bd = ByteData.sublistView(b);
    return bd.getUint32(off, Endian.little) + bd.getUint32(off + 4, Endian.little) * 4294967296;
  }

  static Uint8List _cat(List<List<int>> parts) {
    final b = BytesBuilder(copy: false);
    for (final p in parts) {
      b.add(p);
    }
    return b.takeBytes();
  }
}

/// OLE Compound File (CFB) 최소 읽기: 스트림 이름으로 내용을 꺼낸다.
class _Cfb {
  _Cfb(this.data) {
    final bd = ByteData.sublistView(data);
    int u16(int o) => bd.getUint16(o, Endian.little);
    int u32(int o) => bd.getUint32(o, Endian.little);
    _ss = 1 << u16(30);
    _mss = 1 << u16(32);
    final nFat = u32(44);
    final dirStart = u32(48);
    _cutoff = u32(56);
    final miniFatStart = u32(60);
    final nMiniFat = u32(64);
    var difStart = u32(68);
    final nDif = u32(72);

    final difat = <int>[for (var i = 0; i < 109; i++) u32(76 + 4 * i)];
    for (var n = 0; n < nDif && difStart < 0xFFFFFFFA; n++) {
      final o = _off(difStart);
      final per = _ss ~/ 4;
      for (var i = 0; i < per - 1; i++) {
        difat.add(u32(o + 4 * i));
      }
      difStart = u32(o + 4 * (per - 1));
    }
    for (final fs in difat.take(nFat)) {
      final o = _off(fs);
      for (var i = 0; i < _ss ~/ 4; i++) {
        _fat.add(u32(o + 4 * i));
      }
    }
    final dir = _readChain(dirStart, _fat, _ss, _sector);
    final dbd = ByteData.sublistView(dir);
    for (var o = 0; o + 128 <= dir.length; o += 128) {
      final nl = dbd.getUint16(o + 64, Endian.little);
      final nameBytes = nl >= 2 ? dir.sublist(o, o + nl - 2) : Uint8List(0);
      final codes = <int>[
        for (var i = 0; i + 1 < nameBytes.length; i += 2) nameBytes[i] | (nameBytes[i + 1] << 8)
      ];
      _entries.add(_Entry(
        String.fromCharCodes(codes),
        dir[o + 66],
        dbd.getUint32(o + 116, Endian.little),
        dbd.getUint32(o + 120, Endian.little),
      ));
    }
    if (_entries.isNotEmpty) {
      final root = _entries.first;
      _ministream = _readChain(root.start, _fat, _ss, _sector);
      if (_ministream.length > root.size) _ministream = _ministream.sublist(0, root.size);
    }
    if (nMiniFat > 0) {
      final mf = _readChain(miniFatStart, _fat, _ss, _sector);
      final mbd = ByteData.sublistView(mf);
      for (var i = 0; i + 4 <= mf.length; i += 4) {
        _miniFat.add(mbd.getUint32(i, Endian.little));
      }
    }
  }

  final Uint8List data;
  late final int _ss, _mss, _cutoff;
  final _fat = <int>[];
  final _miniFat = <int>[];
  final _entries = <_Entry>[];
  Uint8List _ministream = Uint8List(0);

  int _off(int sector) => (sector + 1) * _ss;

  Uint8List _sector(int i) {
    final o = _off(i);
    if (o + _ss > data.length) {
      return Uint8List.fromList([
        ...data.sublist(o < data.length ? o : data.length),
        ...List.filled(o + _ss - (o < data.length ? data.length : o), 0),
      ]);
    }
    return data.sublist(o, o + _ss);
  }

  Uint8List _miniSector(int i) {
    final o = i * _mss;
    final end = o + _mss > _ministream.length ? _ministream.length : o + _mss;
    return _ministream.sublist(o < end ? o : end, end);
  }

  static Uint8List _readChain(
      int start, List<int> table, int size, Uint8List Function(int) read) {
    final b = BytesBuilder(copy: false);
    var c = start;
    var guard = 0;
    while (c < 0xFFFFFFFA && c < table.length && guard++ < 1000000) {
      b.add(read(c));
      c = table[c];
    }
    return b.takeBytes();
  }

  bool has(String name) => _entries.any((e) => e.name == name && e.type == 2);

  Uint8List? stream(String name) {
    for (final e in _entries) {
      if (e.name != name || e.type != 2) continue;
      final raw = e.size < _cutoff
          ? _readChain(e.start, _miniFat, _mss, _miniSector)
          : _readChain(e.start, _fat, _ss, _sector);
      return raw.length > e.size ? raw.sublist(0, e.size) : raw;
    }
    return null;
  }
}

class _Entry {
  _Entry(this.name, this.type, this.start, this.size);
  final String name;
  final int type;
  final int start;
  final int size;
}
