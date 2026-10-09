import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kid_med_check/logic/models.dart';
import 'package:kid_med_check/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 홈 화면이 기록(확인 전 포함)과 함께 오류 없이 그려지는지
void main() {
  testWidgets('홈 화면: 확인 전 기록이 있어도 열린다', (tester) async {
    final kid = ChildProfile(id: 'c1', name: '하진', birthDate: DateTime(2020, 1, 1));
    final recs = [
      MedRecord(
          id: 'r1',
          childId: 'c1',
          title: '6월 3일 처방',
          createdAt: DateTime(2026, 6, 3),
          drugs: ['타이레놀정500밀리그램', '세프트리악손주1g']),
      MedRecord(id: 'r2', childId: 'c1', title: '7월 1일 약국 구입', createdAt: DateTime(2026, 7, 1), otc: true),
    ];
    SharedPreferences.setMockInitialValues({
      'children': jsonEncode([kid.toJson()]),
      'selectedChildId': 'c1',
      'records': jsonEncode(recs.map((r) => r.toJson()).toList()),
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomScrollView), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}
