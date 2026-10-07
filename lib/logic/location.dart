/// 대략적 위치 (가까운 병원·약국을 고를 때만 씀). 앱 실행 중 한 번 얻으면 다시 묻지 않는다.
library;

import 'package:geolocator/geolocator.dart';

(double, double)? _lastPos;

/// (위도, 경도). 권한이 없거나 위치가 꺼져 있으면 null.
/// [ask]가 false면 권한을 새로 묻지 않는다 (화면을 열 때 몰래 팝업이 뜨지 않게).
Future<(double, double)?> roughPosition({bool ask = true}) async {
  if (_lastPos != null) return _lastPos;
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied && ask) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return null;
    }
    final last = await Geolocator.getLastKnownPosition();
    final p = last ??
        await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)));
    _lastPos = (p.latitude, p.longitude);
    return _lastPos;
  } catch (_) {
    return null;
  }
}
