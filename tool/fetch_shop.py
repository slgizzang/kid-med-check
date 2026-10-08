"""쿠팡 파트너스 상품 검색으로 docs/shop.json 을 갱신한다 (GitHub Actions 에서 실행).

- 키: 저장소 Secrets 의 COUPANG_ACCESS_KEY / COUPANG_SECRET_KEY (없으면 아무것도 안 함)
- 쿠팡 검색 API 는 시간당 호출 수가 적어서, 한 번에 오래된 검색어 몇 개씩만 갱신한다.
- 결과 링크는 파트너스 링크(구매 시 수수료). 가격 낮은 순으로 저장.
"""
import datetime
import hashlib
import hmac
import json
import os
import pathlib
import sys
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
KW_FILE = ROOT / "docs" / "shop_keywords.json"
OUT = ROOT / "docs" / "shop.json"
PER_RUN = 8  # 시간당 제한(약 10회) 안쪽
HOST = "https://api-gateway.coupang.com"
PATH = "/v2/providers/affiliate_open_api/apis/openapi/products/search"

ak = os.environ.get("COUPANG_ACCESS_KEY", "").strip()
sk = os.environ.get("COUPANG_SECRET_KEY", "").strip()
if not ak or not sk:
    print("쿠팡 파트너스 키가 없어 건너뜀")
    sys.exit(0)


def search(keyword: str, limit: int = 10):
    query = urllib.parse.urlencode({"keyword": keyword, "limit": limit})
    signed = datetime.datetime.now(datetime.timezone.utc).strftime("%y%m%dT%H%M%SZ")
    msg = signed + "GET" + PATH + query
    sig = hmac.new(sk.encode(), msg.encode(), hashlib.sha256).hexdigest()
    auth = f"CEA algorithm=HmacSHA256, access-key={ak}, signed-date={signed}, signature={sig}"
    req = urllib.request.Request(f"{HOST}{PATH}?{query}", headers={"Authorization": auth})
    with urllib.request.urlopen(req, timeout=20) as r:
        d = json.loads(r.read().decode("utf-8"))
    items = []
    for p in (d.get("data") or {}).get("productData") or []:
        try:
            price = int(p.get("productPrice") or 0)
        except (TypeError, ValueError):
            price = 0
        url = p.get("productUrl") or ""
        if not url or price <= 0:
            continue
        items.append({
            "name": p.get("productName", ""),
            "price": price,
            "image": p.get("productImage", ""),
            "url": url,
            "rocket": bool(p.get("isRocket")),
            "freeShip": bool(p.get("isFreeShipping")),
        })
    items.sort(key=lambda x: x["price"])
    return items


keywords = json.loads(KW_FILE.read_text(encoding="utf-8"))["keywords"]
data = json.loads(OUT.read_text(encoding="utf-8")) if OUT.exists() else {"items": {}, "updated": {}}
data.setdefault("items", {})
data.setdefault("updated", {})
# 가장 오래전에 갱신한 검색어부터
order = sorted(keywords, key=lambda k: data["updated"].get(k, ""))
now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
done = 0
for kw in order[:PER_RUN]:
    try:
        data["items"][kw] = search(kw)
        data["updated"][kw] = now
        done += 1
        print(f"{kw}: {len(data['items'][kw])}개")
    except Exception as e:  # noqa: BLE001
        print(f"{kw}: 실패 {type(e).__name__} {str(e)[:120]}")
# 목록에서 빠진 검색어는 정리
for k in list(data["items"]):
    if k not in keywords:
        data["items"].pop(k, None)
        data["updated"].pop(k, None)
data["source"] = "coupang_partners"
OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"갱신 {done}개")
