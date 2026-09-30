"""CI에서 실제 식약처 DUR API를 한 번 호출해 키 동작 여부와 응답 형태를 기록한다.
키 값은 절대 출력하지 않는다."""
import json
import os
import urllib.parse
import urllib.request

key = os.environ.get("DUR_API_KEY", "")
out = []
if not key:
    out.append("API 점검: 인증키가 설정되지 않은 빌드입니다 (사용자가 설정에서 입력해야 함).")
else:
    base = "https://apis.data.go.kr/1471000/DURPrdlstInfoService03/getSpcifyAgrdeTabooInfoList03"
    for name in ["코대원", "정"]:
        q = urllib.parse.urlencode(
            {"serviceKey": key, "type": "json", "pageNo": 1, "numOfRows": 3, "itemName": name}
        )
        try:
            with urllib.request.urlopen(f"{base}?{q}", timeout=30) as r:
                body = r.read().decode("utf-8", "replace")
            try:
                d = json.loads(body)
                root = d.get("response", d)
                header = root.get("header", {})
                b = root.get("body", {})
                items = b.get("items", [])
                if isinstance(items, dict):
                    items = items.get("item", [])
                if isinstance(items, dict):
                    items = [items]
                items = [i.get("item", i) if isinstance(i, dict) else i for i in items]
                out.append(
                    f"[{name}] resultCode={header.get('resultCode')} totalCount={b.get('totalCount')}"
                )
                if items:
                    first = items[0]
                    out.append(f"  fields: {', '.join(first.keys())}")
                    for k in ("ITEM_NAME", "INGR_KOR_NAME", "PROHBT_CONTENT", "REMARK"):
                        if k in first:
                            out.append(f"  {k}: {str(first[k])[:120]}")
            except json.JSONDecodeError:
                out.append(f"[{name}] JSON 아님: {body[:300]}")
        except Exception as e:  # noqa: BLE001
            out.append(f"[{name}] 호출 실패: {type(e).__name__}: {str(e)[:200]}")

    extra = [
        ("e약은요", "https://apis.data.go.kr/1471000/DrbEasyDrugInfoService/getDrbEasyDrugList", "타이레놀"),
        ("DUR품목", "https://apis.data.go.kr/1471000/DURPrdlstInfoService03/getDurPrdlstInfoList03", "세토펜"),
    ]
    for label, url, name in extra:
        q = urllib.parse.urlencode(
            {"serviceKey": key, "type": "json", "pageNo": 1, "numOfRows": 1, "itemName": name}
        )
        try:
            with urllib.request.urlopen(f"{url}?{q}", timeout=30) as r:
                body = r.read().decode("utf-8", "replace")
            try:
                d = json.loads(body)
                root = d.get("response", d)
                b = root.get("body", {})
                items = b.get("items", [])
                if isinstance(items, dict):
                    items = items.get("item", [])
                if isinstance(items, dict):
                    items = [items]
                out.append(f"[{label}:{name}] resultCode={root.get('header', {}).get('resultCode')} totalCount={b.get('totalCount')}")
                if items:
                    first = items[0]
                    out.append(f"  fields: {', '.join(first.keys())}")
                    for k in ("itemName", "efcyQesitm", "ITEM_NAME", "CLASS_NAME", "ETC_OTC_NAME", "MAIN_INGR"):
                        if k in first:
                            out.append(f"  {k}: {str(first[k])[:100]}")
            except json.JSONDecodeError:
                out.append(f"[{label}] JSON 아님: {body[:300]}")
        except Exception as e:  # noqa: BLE001
            out.append(f"[{label}] 호출 실패: {type(e).__name__}: {str(e)[:200]}")

    # DUR 성분정보: 성분별 특정연령대금기 (연령 기준 필드 확인용) - 서비스 이름 후보를 차례로 시도
    import urllib.error
    for svc, op in [("DURIrdntInfoService03", "getSpcifyAgrdeTabooInfoList03"),
                    ("DURIrdntInfoService02", "getSpcifyAgrdeTabooInfoList02"),
                    ("DURIrdntInfoService01", "getSpcifyAgrdeTabooInfoList01")]:
        url = f"https://apis.data.go.kr/1471000/{svc}/{op}"
        q = urllib.parse.urlencode({"serviceKey": key, "type": "json", "pageNo": 1, "numOfRows": 3})
        try:
            with urllib.request.urlopen(f"{url}?{q}", timeout=30) as r:
                body = r.read().decode("utf-8", "replace")
            try:
                d = json.loads(body)
                root = d.get("response", d)
                b2 = root.get("body", {})
                items = b2.get("items", [])
                if isinstance(items, dict):
                    items = items.get("item", [])
                if isinstance(items, dict):
                    items = [items]
                out.append(f"[DUR성분 {svc}] resultCode={root.get('header', {}).get('resultCode')} totalCount={b2.get('totalCount')}")
                for it in items[:3]:
                    it = it.get("item", it) if isinstance(it, dict) else it
                    out.append("  " + " | ".join(f"{k}={str(v)[:40]}" for k, v in it.items()))
                break
            except json.JSONDecodeError:
                out.append(f"[DUR성분 {svc}] JSON 아님: {body[:200]}")
        except urllib.error.HTTPError as e:
            detail = " ".join(e.read().decode("utf-8", "replace").split())[:300] if hasattr(e, "read") else ""
            out.append(f"[DUR성분 {svc}] HTTP {e.code}: {detail}")
        except Exception as e:  # noqa: BLE001
            out.append(f"[DUR성분 {svc}] 호출 실패: {type(e).__name__}: {str(e)[:150]}")

text = "\n".join(out).replace(key, "***") if key else "\n".join(out)
print(text)
with open("api_smoke.txt", "w", encoding="utf-8") as f:
    f.write(text + "\n")
