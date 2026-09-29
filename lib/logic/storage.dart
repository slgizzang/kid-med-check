import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 빌드할 때 --dart-define=DUR_API_KEY=... 로 넣은 기본 키 (없으면 빈 문자열)
const String kBuiltInApiKey = String.fromEnvironment('DUR_API_KEY');

/// 개발자가 빌드 때 키를 넣었으면 사용자는 키를 볼 일도, 입력할 일도 없다.
const bool kHasBuiltInKey = kBuiltInApiKey != '';

class AppStorage {
  static const _kChildren = 'children';
  static const _kSelected = 'selectedChildId';
  static const _kApiKey = 'apiKey';

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
}
