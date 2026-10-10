import 'package:flutter/foundation.dart';
import 'dur_api.dart';
import 'place_resolver.dart' as place;
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'reaction.dart';
import 'hira_import.dart';

/// 빌드할 때 --dart-define=DUR_API_KEY=... 로 넣은 기본 키 (없으면 빈 문자열)
const String kBuiltInApiKey = String.fromEnvironment('DUR_API_KEY');

/// 개발자가 빌드 때 키를 넣었으면 사용자는 키를 볼 일도, 입력할 일도 없다.
const bool kHasBuiltInKey = kBuiltInApiKey != '';

class AppStorage {
  static const _kChildren = 'children';
  static const _kSelected = 'selectedChildId';
  static const _kApiKey = 'apiKey';
  static const _kRecords = 'records';
  static const _kReactions = 'reactions';

  static Future<String> apiKey() async {
    if (kHasBuiltInKey) return kBuiltInApiKey;
    final p = await SharedPreferences.getInstance();
    final saved = p.getString(_kApiKey) ?? '';
    return saved.isNotEmpty ? saved : kBuiltInApiKey;
  }

  static Future<void> setApiKey(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kApiKey, key.trim());
  }

  static Future<List<ChildProfile>> children() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kChildren);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ChildProfile.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveChildren(List<ChildProfile> children) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kChildren, jsonEncode(children.map((c) => c.toJson()).toList()));
  }

  static Future<String?> selectedChildId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kSelected);
  }

  static Future<void> setSelectedChildId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSelected, id);
  }

  static Future<List<MedRecord>> records() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kRecords);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => MedRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveRecords(List<MedRecord> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kRecords, jsonEncode(list.map((r) => r.toJson()).toList()));
  }

  static Future<void> saveRecord(MedRecord r) async {
    final list = await records();
    final i = list.indexWhere((x) => x.id == r.id);
    if (i >= 0) {
      list[i] = r;
    } else {
      list.add(r);
    }
    await _saveRecords(list);
  }

  /// 실손24 연계 결과만 한 번에 저장 (그사이 다른 곳에서 바뀐 내용은 그대로 둔다)
  static Future<void> saveSilson(List<MedRecord> changed) async {
    if (changed.isEmpty) return;
    final byId = {for (final r in changed) r.id: r};
    final list = await records();
    for (final r in list) {
      final c = byId[r.id];
      if (c == null) continue;
      r
        ..silsonH = c.silsonH
        ..silsonP = c.silsonP;
    }
    await _saveRecords(list);
  }

  static Future<void> deleteRecord(String id) async {
    final list = await records();
    for (final r in list.where((x) => x.id == id)) {
      _deletePhotos(r);
    }
    list.removeWhere((x) => x.id == id);
    await _saveRecords(list);
  }

  /// 기록을 지울 때 찍어둔 사진 파일도 지운다
  static void _deletePhotos(MedRecord r) {
    for (final p in r.photos) {
      try {
        File(p.path).deleteSync();
      } catch (_) {}
    }
  }

  /// 병원·약국 위치가 없는 기록에 심평원 정보로 위치·주소·코드를 채워 저장한다.
  /// [childId]를 주면 그 복용자 기록만. 바뀐 기록 수를 돌려준다.
  static Future<int> fillPlaces({String? childId, void Function(int, int)? onProgress}) async {
    final list = await records();
    final mine = childId == null ? list : list.where((r) => r.childId == childId).toList();
    final n = await place.fillPlaces(DurApi(await apiKey()), mine, onProgress: onProgress);
    if (n > 0) {
      await _saveRecords(list);
      placesChanged.value++;
    }
    return n;
  }

  /// 병원·약국 위치를 뒤에서 채운 뒤 화면을 다시 그리도록 알리는 값
  static final placesChanged = ValueNotifier<int>(0);

  /// 사용자가 고른 병원·약국을 같은 이름의 다른 기록에도 적용 (아직 위치가 정해지지 않은 것만).
  /// 같은 사람의 기록에서 같은 이름은 같은 곳으로 본다.
  static Future<int> applyPlace(String childId, String name,
      {required bool pharmacy, required PlaceHit hit}) async {
    String n(String x) => x.replaceAll(RegExp(r'\s'), '');
    final list = await records();
    var count = 0;
    for (final r in list.where((r) => r.childId == childId)) {
      final rn = pharmacy ? r.pharmacy : place.hospitalNameOf(r);
      final pos = pharmacy ? r.pharmacyPos : r.hospitalPos;
      if (pos != null || n(rn) != n(name)) continue;
      final p = hit.lat != null && hit.lng != null ? (hit.lat!, hit.lng!) : null;
      if (pharmacy) {
        r.pharmacyAddr = hit.addr;
        r.pharmacyCode = hit.code;
        r.pharmacyPos = p;
      } else {
        if (r.hospital.isEmpty) r.hospital = rn;
        r.hospitalAddr = hit.addr;
        r.hospitalCode = hit.code;
        r.hospitalPos = p;
      }
      count++;
    }
    if (count > 0) await _saveRecords(list);
    return count;
  }

  /// 불러온 처방을 기록으로 저장. 이미 불러온 것은 건너뛴다. (새로 만든 수, 건너뛴 수)
  static Future<(int, int)> importVisits(String childId, List<ImportedVisit> visits) async {
    final list = await records();
    final have = {
      for (final r in list)
        if (r.childId == childId && r.importKey != null) r.importKey!
    };
    var added = 0, skipped = 0;
    for (final v in visits) {
      if (have.contains(v.key)) {
        // 예전에 불러온 기록에 병원·약국 이름이 없으면 채워 둔다
        for (final r in list) {
          if (r.childId != childId || r.importKey != v.key) continue;
          if (r.hospital.isEmpty) r.hospital = v.hospital;
          r.safetyLetters.addAll(v.safetyLetters);
          // 원내 조제 여부는 새로 읽은 파일 기준으로 바로잡는다
          // (예전 버전은 주사만 병원에서 받은 날도 원내 조제로 잘못 표시했음)
          if (v.inHouse) {
            if (!r.inHouse) {
              r.inHouse = true;
              r.pharmacy = '';
              r.pharmacyAddr = '';
              r.pharmacyCode = '';
              r.pharmacyPos = null;
            }
          } else {
            if (r.inHouse) r.inHouse = false;
            if (r.pharmacy.isEmpty && v.pharmacy.isNotEmpty) r.pharmacy = v.pharmacy;
          }
        }
        skipped++;
        continue;
      }
      list.add(MedRecord(
        id: '${DateTime.now().microsecondsSinceEpoch}_$added',
        childId: childId,
        title: v.title,
        createdAt: v.date,
        drugs: List.of(v.drugs),
        importKey: v.key,
        hospital: v.hospital,
        pharmacy: v.pharmacy,
        inHouse: v.inHouse,
        safetyLetters: Map.of(v.safetyLetters),
      ));
      have.add(v.key);
      added++;
    }
    await _saveRecords(list);
    return (added, skipped);
  }

  /// 아이를 지우면 그 아이의 기록(처방·반응)도 지운다.
  static Future<void> deleteRecordsOfChild(String childId) async {
    final list = await records();
    for (final r in list.where((x) => x.childId == childId)) {
      _deletePhotos(r);
    }
    list.removeWhere((x) => x.childId == childId);
    await _saveRecords(list);
    final notes = await _allReactions();
    notes.removeWhere((x) => x.childId == childId);
    await _saveReactions(notes);
  }

  static Future<List<ReactionNote>> _allReactions() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kReactions);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => ReactionNote.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveReactions(List<ReactionNote> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kReactions, jsonEncode(list.map((r) => r.toJson()).toList()));
  }

  static Future<List<ReactionNote>> allReactions() => _allReactions();

  /// 이 복용자의 반응 기록
  static Future<List<ReactionNote>> reactions(String childId) async =>
      (await _allReactions()).where((x) => x.childId == childId).toList();

  static Future<void> saveReaction(ReactionNote n) async {
    final list = await _allReactions();
    final i = list.indexWhere((x) => x.id == n.id);
    if (i >= 0) {
      list[i] = n;
    } else {
      list.add(n);
    }
    await _saveReactions(list);
  }

  static Future<void> deleteReaction(String id) async {
    final list = await _allReactions();
    list.removeWhere((x) => x.id == id);
    await _saveReactions(list);
  }
}
