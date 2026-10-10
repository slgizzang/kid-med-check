// 플레이 스토어용 화면 캡처 (예시 데이터). `flutter test test_store` 로 실행하면 build/store/*.png 생성.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kid_med_check/logic/models.dart';
import 'package:kid_med_check/logic/recall.dart';
import 'package:kid_med_check/logic/snapshot.dart';
import 'package:kid_med_check/screens/home_screen.dart';
import 'package:kid_med_check/screens/record_screen.dart';
import 'package:kid_med_check/screens/result_screen.dart';
import 'package:kid_med_check/screens/splash_screen.dart';
import 'package:kid_med_check/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _k = GlobalKey();

Future<void> _loadFonts() async {
  // 버튼 등 테마 글꼴을 따로 쓰는 곳(Roboto)도 Pretendard로 (실제 폰에서는 시스템 한글 글꼴이 쓰임)
  for (final family in ['Pretendard', 'Roboto']) {
    final l = FontLoader(family);
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      l.addFont(rootBundle.load('assets/fonts/Pretendard-$w.otf'));
    }
    await l.load();
  }
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await l.load();
  }
}

Widget _app(Widget home) => RepaintBoundary(
      key: _k,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    );

Future<void> _settle(WidgetTester t, [int ms = 1500]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// 화면을 닫고 남은 타이머(시작 화면 이동, 자동 확인 제한 시간 등)를 흘려보낸다
Future<void> _close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(minutes: 2));
}

Future<void> _shot(WidgetTester t, String name) async {
  await t.runAsync(() async {
    final ro = t.renderObject<RenderRepaintBoundary>(find.byKey(_k));
    final img = await ro.toImage(pixelRatio: 3);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File('build/store/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

final kid = ChildProfile(id: 'c1', name: '하진', birthDate: DateTime(2020, 3, 15));

ResultSnapshot _snap(DateTime at, List<DrugSnap> drugs, {List<String> mix = const []}) =>
    ResultSnapshot(at: at, drugs: drugs, mixPairs: mix, pregnant: false, nursing: false);

MedRecord _rec(String id, DateTime d, String hospital, List<String> drugs,
    {String pharmacy = '', bool otc = false, String h = '', String p = '',
    Map<String, String>? letters, List<DrugSnap>? snaps}) {
  final r = MedRecord(
    id: id,
    childId: 'c1',
    title: '${d.month}월 ${d.day}일 ${otc ? pharmacy : hospital}',
    createdAt: d,
    drugs: drugs,
    otc: otc,
    hospital: hospital,
    pharmacy: pharmacy,
    hospitalPos: hospital.isEmpty ? null : (37.5, 127.0),
    pharmacyPos: pharmacy.isEmpty ? null : (37.5, 127.0),
    importKey: otc ? null : 'k$id',
    safetyLetters: letters,
  )
    ..silsonH = h
    ..silsonP = p;
  r.last = _snap(d, snaps ?? [for (final x in drugs) DrugSnap(query: x, title: x)]);
  return r;
}

final records = [
  _rec('r1', DateTime(2026, 9, 21), '맑은숲이비인후과의원',
      ['코대원포르테시럽', '오구멘틴듀오시럽', '부루펜시럽'],
      pharmacy: '온누리하늘약국', h: 'on', p: 'on', snaps: [
    DrugSnap(query: '코대원포르테시럽', title: '코대원포르테시럽', ageRule: '12세 미만'),
    DrugSnap(query: '오구멘틴듀오시럽', title: '오구멘틴듀오시럽'),
    DrugSnap(query: '부루펜시럽', title: '부루펜시럽'),
  ]),
  _rec('r2', DateTime(2026, 9, 2), '새싹소아청소년과의원', ['챔프시럽', '액시마건조시럽'],
      pharmacy: '푸른솔약국', h: 'on', p: 'on'),
  _rec('r3', DateTime(2026, 8, 14), '연세봄소아청소년과의원', ['세파클러건조시럽', '뮤테란과립'],
      pharmacy: '건강한약국', h: 'on', p: 'off'),
  _rec('r4', DateTime(2026, 7, 30), '', ['어린이부루펜시럽'], pharmacy: '행복한약국', otc: true),
  _rec('r5', DateTime(2026, 6, 9), '아이사랑소아과의원', ['페니라민시럽', '코푸시럽'],
      pharmacy: '미소약국', h: 'off', letters: {'코푸시럽': '안전성서한'}),
];

void _seed() {
  SharedPreferences.setMockInitialValues({
    'children': jsonEncode([kid.toJson()]),
    'selectedChildId': 'c1',
    'records': jsonEncode(records.map((r) => r.toJson()).toList()),
    'recalls1': jsonEncode({
      't': DateTime.now().millisecondsSinceEpoch,
      'i': [
        Recall(
                product: '세파클러건조시럽',
                company: '예시제약',
                reason: '함량 부적합',
                date: DateTime(2026, 9, 1))
            .toJson()
      ],
    }),
  });
}

void main() {
  setUpAll(_loadFonts);

  setUp(() {
    final v = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first as TestFlutterView;
    v.physicalSize = const Size(1080, 2160);
    v.devicePixelRatio = 3;
  });

  testWidgets('1 시작 화면', (t) async {
    _seed();
    await t.pumpWidget(_app(const SplashScreen()));
    // 로고가 다 나타난 뒤(0.7초 애니메이션), 다음 화면으로 넘어가기 전(2초)
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await _shot(t, '1_splash');
    await _close(t);
  });

  testWidgets('2·3 메인 화면', (t) async {
    _seed();
    await t.pumpWidget(_app(const HomeScreen()));
    await _settle(t, 4000);
    // 맨 위 소개 부분을 넘겨 안전 점검이 보이게
    await t.drag(find.byType(CustomScrollView).first, const Offset(0, -330));
    await _settle(t, 800);
    await _shot(t, '2_home_safety');
    await t.drag(find.byType(CustomScrollView).first, const Offset(0, -620));
    await _settle(t, 800);
    await _shot(t, '3_home_claim');
    await _close(t);
  });

  testWidgets('4 복용 기록', (t) async {
    _seed();
    await t.pumpWidget(_app(RecordScreen(child: kid, record: records[0])));
    await _settle(t, 3000);
    await _shot(t, '4_record');
    await _close(t);
  });

  testWidgets('5 안전 확인 결과', (t) async {
    _seed();
    final r = records[2];
    final checks = [
      for (final d in r.drugs)
        DrugCheck(d)
          ..status = CheckStatus.notListed
          ..infoLoading = false
    ];
    final hit = RecallHit(r, '세파클러건조시럽',
        Recall(product: '세파클러건조시럽', reason: '함량 부적합', date: DateTime(2026, 9, 1)));
    await t.pumpWidget(_app(ResultScreen(
      child: kid,
      record: r,
      names: r.drugs,
      recordId: r.id,
      asOf: r.createdAt,
      reuse: checks,
      recalls: {'세파클러건조시럽': hit},
    )));
    await _settle(t, 2500);
    await _shot(t, '5_result');
    await _close(t);
  });
}
