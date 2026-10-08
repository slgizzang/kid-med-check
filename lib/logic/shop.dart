/// 복용 리포트의 생활 관리·영양제 참고 → 관련 상품 목록 (쿠팡 파트너스).
/// 상품 목록은 GitHub Actions(shop-update)가 매시간 조금씩 갱신해 docs/shop.json 으로 올린다.
/// 앱은 그 파일만 읽는다 (쿠팡 키는 앱에 넣지 않음). 하루에 한 번만 새로 받는다.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const kShopUrl = 'https://raw.githubusercontent.com/slgizzang/kid-med-check/main/docs/shop.json';

/// 쿠팡 파트너스 고지 문구 (파트너스 이용 약관상 표시 필요)
const kShopDisclosure =
    '네이버 가격비교 목록은 네이버 쇼핑 검색 결과예요. 쿠팡 목록은 쿠팡 파트너스 활동의 일환으로, '
    '이를 통해 구매하면 필세이프가 일정액의 수수료를 받을 수 있어요. 구매하시는 가격은 똑같아요.';

class ShopItem {
  const ShopItem(
      {required this.name,
      required this.price,
      required this.url,
      this.image = '',
      this.rocket = false,
      this.freeShip = false,
      this.brand = ''});

  final String name;
  final int price;
  final String url;
  final String image;
  final bool rocket;
  final bool freeShip;
  final String brand;

  factory ShopItem.fromJson(Map<String, dynamic> j) => ShopItem(
        name: '${j['name'] ?? ''}',
        price: (j['price'] as num?)?.toInt() ?? 0,
        url: '${j['url'] ?? ''}',
        image: '${j['image'] ?? ''}',
        rocket: j['rocket'] == true,
        freeShip: j['freeShip'] == true,
        brand: '${j['brand'] ?? ''}',
      );
}

/// 팁 제목 → 보여줄 검색어 (아이·어른 따로)
List<String> shopKeywordsFor(String tipTitle, {required bool child}) {
  if (tipTitle.contains('유산균')) return [child ? '어린이 유산균' : '유산균'];
  if (tipTitle.contains('장 건강')) {
    return child ? ['어린이 유산균', '어린이 식이섬유'] : ['유산균', '식이섬유'];
  }
  if (tipTitle.contains('비타민D') || tipTitle.contains('칼슘')) {
    return child ? ['어린이 비타민D', '어린이 칼슘'] : ['비타민D', '칼슘 마그네슘'];
  }
  if (tipTitle.contains('호흡기')) return ['가습기', '온습도계'];
  if (tipTitle.contains('해열')) return [child ? '아기 체온계' : '체온계'];
  return const [];
}

/// 파트너스 목록이 아직 없을 때 쓰는 쿠팡 검색 주소 (수수료 없음)
String shopSearchUrl(String keyword) =>
    'https://www.coupang.com/np/search?q=${Uri.encodeQueryComponent(keyword)}';

String formatPrice(int won) {
  final s = won.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '$b원';
}

/// 검색어별 상품: 네이버 가격비교(인기순, 전체 쇼핑몰 최저가) + 쿠팡 파트너스(낮은 가격순)
class ShopData {
  const ShopData({this.naver = const {}, this.coupang = const {}});
  final Map<String, List<ShopItem>> naver;
  final Map<String, List<ShopItem>> coupang;
}

class Shop {
  static ShopData? _mem;
  static const _key = 'shop1';

  static Map<String, List<ShopItem>> _group(dynamic items) {
    if (items is! Map) return {};
    return {
      for (final e in items.entries)
        '${e.key}': [
          for (final x in (e.value as List? ?? const []))
            if (x is Map) ShopItem.fromJson(Map<String, dynamic>.from(x))
        ]..removeWhere((i) => i.url.isEmpty || i.price <= 0)
    };
  }

  static ShopData parse(String body) {
    final d = jsonDecode(body);
    if (d is! Map) return const ShopData();
    return ShopData(naver: _group(d['naver']), coupang: _group(d['items']));
  }

  /// 받지 못하면 빈 목록.
  static Future<ShopData> load({http.Client? client}) async {
    if (_mem != null) return _mem!;
    SharedPreferences? p;
    try {
      p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null) {
        final j = jsonDecode(raw) as Map;
        final t = DateTime.fromMillisecondsSinceEpoch(j['t'] as int);
        if (DateTime.now().difference(t) < const Duration(hours: 24)) {
          return _mem = parse(j['b'] as String);
        }
      }
    } catch (_) {}
    try {
      final r = await (client ?? http.Client())
          .get(Uri.parse(kShopUrl))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final body = utf8.decode(r.bodyBytes);
        final m = parse(body);
        await p?.setString(
            _key, jsonEncode({'t': DateTime.now().millisecondsSinceEpoch, 'b': body}));
        return _mem = m;
      }
    } catch (_) {}
    return const ShopData();
  }
}
