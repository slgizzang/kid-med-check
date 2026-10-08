import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'logic/dur_api.dart';
import 'screens/splash_screen.dart';
import 'ui/theme.dart';

void main() {
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
    );
  }
}
