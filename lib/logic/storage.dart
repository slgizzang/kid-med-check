import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'reaction.dart';

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

  static Future<void> deleteRecord(String id) async {
    final list = await records();
    list.removeWhere((x) => x.id == id);
    await _saveRecords(list);
  }

  /// 아이를 지우면 그 아이의 기록(처방·반응)도 지운다.
  static Future<void> deleteRecordsOfChild(String childId) async {
    final list = await records();
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
