"""상품 목록 docs/shop.json 갱신 (GitHub Actions 에서 실행). 두 출처를 따로 저장한다.

1) 네이버 쇼핑 검색 API — 가격비교 상품을 네이버 인기(정확도)순으로, 상품마다 전체 쇼핑몰 최저가.
   키: NAVER_CLIENT_ID / NAVER_CLIENT_SECRET. 하루 호출 한도가 넉넉해 12시간마다 전부 갱신.
2) 쿠팡 파트너스 검색 API — 쿠팡 상품을 가격 낮은 순, 링크는 파트너스 링크(구매 시 수수료).
   키: COUPANG_ACCESS_KEY / COUPANG_SECRET_KEY. 시간당 호출 수가 적어 오래된 검색어부터 몇 개씩.
키가 없는 출처는 건너뛴다.
"""
import html
import re
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
nid = os.environ.get("NAVER_CLIENT_ID", "").strip()
nsec = os.environ.get("NAVER_CLIENT_SECRET", "").strip()
if not (ak and sk) and not (nid and nsec):
    print("상품 검색 키가 없어 건너뜀")
    sys.exit(0)


def naver(keyword: str):
    """네이버 가격비교 상품(productType 1)만, 네이버 정확도(인기)순 그대로."""
    q = urllib.parse.urlencode({"query": keyword, "display": 40, "sort": "sim"})
    req = urllib.request.Request(
        f"https://openapi.naver.com/v1/search/shop.json?{q}",
        headers={"X-Naver-Client-Id": nid, "X-Naver-Client-Secret": nsec},
    )
    with urllib.request.urlopen(req, timeout=20) as r:
        d = json.loads(r.read().decode("utf-8"))
    out = []
    for it in d.get("items") or []:
        if str(it.get("productType")) != "1":  # 가격비교로 묶인 상품만 (여러 쇼핑몰 최저가)
            continue
        try:
            price = int(it.get("lprice") or 0)
        except (TypeError, ValueError):
            price = 0
        if price <= 0 or not it.get("link"):
            continue
        out.append({
            "name": html.unescape(re.sub(r"<[^>]+>", "", it.get("title", ""))),
            "price": price,
            "image": it.get("image", ""),
            "url": it.get("link", ""),
            "brand": it.get("brand") or it.get("maker") or "",
        })
        if len(out) >= 6:
            break
    return out


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
data = json.loads(OUT.read_text(encoding="utf-8")) if OUT.exists() else {}
data.setdefault("items", {})  # 쿠팡 (예전 이름 그대로)
data.setdefault("updated", {})
data.setdefault("naver", {})
data.setdefault("naverUpdated", "")

# 1) 네이버: 12시간마다 전부
if nid and nsec:
    last = data.get("naverUpdated") or ""
    stale = True
    if last:
        try:
            age = datetime.datetime.now(datetime.timezone.utc) - datetime.datetime.fromisoformat(last)
            stale = age > datetime.timedelta(hours=12)
        except ValueError:
            pass
    if stale:
        ok = 0
        for kw in keywords:
            try:
                data["naver"][kw] = naver(kw)
                ok += 1
                print(f"[네이버] {kw}: {len(data['naver'][kw])}개")
            except Exception as e:  # noqa: BLE001
                print(f"[네이버] {kw}: 실패 {type(e).__name__} {str(e)[:120]}")
        if ok:
            data["naverUpdated"] = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
        for k in list(data["naver"]):
            if k not in keywords:
                data["naver"].pop(k, None)

if not (ak and sk):
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    sys.exit(0)
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
data["source"] = "naver_shopping+coupang_partners"
OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"갱신 {done}개")
