import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'logic/dur_api.dart';
import 'screens/splash_screen.dart';
import 'ui/theme.dart';

/// 앱에서 난 첫 오류 (원인 확인용으로 화면 아래에 보여준다)
final appError = ValueNotifier<String?>(null);

void _keep(Object e, StackTrace? s) {
  appError.value ??= '$e\n${(s ?? StackTrace.empty).toString().split('\n').take(12).join('\n')}';
}

void main() {
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    _keep(d.exception, d.stack);
  };
  PlatformDispatcher.instance.onError = (e, s) {
    _keep(e, s);
    return true;
  };
  ErrorWidget.builder = (d) => Container(
        color: const Color(0xFFFFEBEE),
        padding: const EdgeInsets.all(8),
        child: Text('화면 오류: ${d.exceptionAsString()}',
            style: const TextStyle(fontSize: 12, color: Color(0xFFC62828))),
      );
  // 번들한 Pretendard 글꼴의 라이선스(SIL OFL)를 앱 라이선스 목록에 등록
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/Pretendard-OFL.txt');
    yield LicenseEntryWithLineBreaks(['Pretendard'], text);
  });
  runApp(const KidMedCheckApp());
  // 오래된 식약처 조회 결과는 지워서 저장 공간이 계속 늘지 않게
  DurApi.pruneCache();
}

class KidMedCheckApp extends StatelessWidget {
  const KidMedCheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SplashScreen(),
      builder: (context, child) => Stack(children: [
        if (child != null) Positioned.fill(child: child),
        ValueListenableBuilder<String?>(
          valueListenable: appError,
          builder: (context, err, _) => err == null
              ? const SizedBox.shrink()
              : Positioned(
                  left: 8,
                  right: 8,
                  bottom: 24,
                  child: Material(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 260),
                            child: SingleChildScrollView(
                              child: SelectableText('오류가 났어요 (이 화면을 캡처해 알려주세요)\n$err',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFFB71C1C))),
                            ),
                          ),
                        ),
                        IconButton(
                            onPressed: () => appError.value = null,
                            icon: const Icon(Icons.close, size: 18)),
                      ]),
                    ),
                  ),
                ),
        ),
      ]),
    );
  }
}
