import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kid_med_check/logic/models.dart';
import 'package:kid_med_check/logic/recall.dart';
import 'package:kid_med_check/main.dart';
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
    // 목록이 실제로 화면을 채워야 한다 (크기 0이면 흰 화면)
    expect(tester.getSize(find.byType(CustomScrollView).first).height, greaterThan(300));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('앱 시작: 시작 화면 다음에 홈이 뜬다', (tester) async {
    final kid = ChildProfile(id: 'c1', name: '하진', birthDate: DateTime(2020, 1, 1));
    SharedPreferences.setMockInitialValues({
      'children': jsonEncode([kid.toJson()]),
      'selectedChildId': 'c1',
      'records': jsonEncode([
        for (var i = 0; i < 40; i++)
          MedRecord(
              id: 'r$i',
              childId: 'c1',
              title: '${i % 12 + 1}월 ${i % 28 + 1}일 처방',
              createdAt: DateTime(2026, i % 12 + 1, i % 28 + 1),
              drugs: ['타이레놀정500밀리그램', '아모잘탄정5/50밀리그램', '세프트리악손주1g'],
              safetyLetters: i == 3 ? {'타이레놀정500밀리그램': '안전성서한'} : null).toJson()
      ]),
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(const KidMedCheckApp());
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });
    expect(appError.value, isNull);
    expect(tester.takeException(), isNull);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.getSize(find.byType(CustomScrollView).first).height, greaterThan(300));
    await tester.pumpWidget(const SizedBox());
  });

  test('회수 대조: 기록 300건 × 회수 1500건을 기록마다 따로 대조해도 빠르다', () {
    final recalls = [
      for (var i = 0; i < 1500; i++)
        Recall(product: '테스트약$i정10밀리그람(성분)', date: DateTime(2026, 6, 10))
    ];
    final recs = [
      for (var i = 0; i < 300; i++)
        MedRecord(
            id: 'r$i',
            childId: 'c',
            title: 't',
            createdAt: DateTime(2026, 6, 1),
            drugs: ['테스트약$i정10밀리그램', '다른약$i'])
    ];
    final sw = Stopwatch()..start();
    var n = 0;
    for (var k = 0; k < 3; k++) {
      for (final r in recs) {
        n += matchRecalls([r], recalls).length;
      }
    }
    sw.stop();
    expect(n, 900);
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });

  test('실손 청구 방법: 병원·약국 연계 결과로 정한다', () {
    MedRecord rec({String h = '', String p = '', String pharmacy = '약국', bool inHouse = false}) =>
        MedRecord(
            id: 'x',
            childId: 'c',
            title: '9월 21일 써니이비인후과의원',
            createdAt: DateTime(2026, 9, 21),
            pharmacy: pharmacy,
            inHouse: inHouse)
          ..silsonH = h
          ..silsonP = p;
    expect(rec().hospitalName, '써니이비인후과의원');
    expect(rec().claimLevel, isNull);
    expect(rec(h: 'on', p: 'on').claimLevel, 0);
    expect(rec(h: 'on', pharmacy: '').claimLevel, 0);
    expect(rec(h: 'on', inHouse: true).claimLevel, 0);
    expect(rec(h: 'on', p: 'off').claimLevel, 1);
    expect(rec(h: 'on').claimLevel, 1);
    expect(rec(h: 'off', p: 'on').claimLevel, 2);
    final back = MedRecord.fromJson(rec(h: 'on', p: 'off').toJson());
    expect((back.silsonH, back.silsonP), ('on', 'off'));
  });
}
