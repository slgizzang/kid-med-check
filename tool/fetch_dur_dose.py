"""식약처 DUR 성분정보의 용량주의(1일 최대 투여량)·투여기간주의(최대 투여기간) 전체 목록을
assets/dur_dose.json 으로 저장한다. 표가 작아서(수백 건) 앱에 통째로 넣는다.

품목 API(DURPrdlstInfoService03)에는 최대량·최대기간 값이 없고, 성분 API에만 있다.
앱은 품목 API로 약의 DUR 성분코드(INGR_CODE)를 얻고, 이 표에서 기준값을 찾는다.

형식: {"dose"|"period": {성분코드: {"n": 성분명, "t": 단일|복합, "e": [{"f": 제형, "m": 기준, "p": 내용, "r": 비고}]}}}
"""
import json, os, pathlib, sys, time, urllib.parse, urllib.request

key = os.environ.get("DUR_API_KEY", "")
if not key:
    sys.exit("DUR_API_KEY 없음")
base = "https://apis.data.go.kr/1471000/DURIrdntInfoService03/"


def s(v):
    return ("" if v is None else str(v)).strip()


def fetch(op, value_key):
    table, page, n = {}, 1, 0
    while True:
        q = {"serviceKey": key, "type": "json", "numOfRows": 100, "pageNo": page}
        for attempt in range(3):
            try:
                d = json.loads(urllib.request.urlopen(base + op + "?" + urllib.parse.urlencode(q), timeout=30).read())
                break
            except Exception:
                if attempt == 2:
                    raise
                time.sleep(2)
        b = d.get("body") or {}
        items = b.get("items") or []
        if isinstance(items, dict):
            items = items.get("item", [])
        if isinstance(items, dict):
            items = [items]
        for it in items:
            it = it.get("item", it)
            if (s(it.get("DEL_YN")) or "정상") != "정상":
                continue
            code, mx = s(it.get("INGR_CODE")), s(it.get(value_key))
            if not code or not mx:
                continue
            n += 1
            t = table.setdefault(code, {"n": s(it.get("INGR_NAME")), "t": s(it.get("MIX_TYPE")), "e": []})
            e = {k: v for k, v in {"f": s(it.get("FORM_NAME")), "m": mx,
                                   "p": s(it.get("PROHBT_CONTENT")), "r": s(it.get("REMARK"))}.items() if v}
            if e not in t["e"]:
                t["e"].append(e)
        total = int(b.get("totalCount") or 0)
        if page * 100 >= total or not items:
            break
        page += 1
    return table, n, total


dose, n1, t1 = fetch("getCpctyAtentInfoList02", "MAX_QTY")
period, n2, t2 = fetch("getMdctnPdAtentInfoList02", "MAX_DOSAGE_TERM")
print(f"용량주의 {n1}/{t1}건 · 성분 {len(dose)}, 투여기간주의 {n2}/{t2}건 · 성분 {len(period)}")
if len(dose) < 100 or len(period) < 20:
    sys.exit("받은 건수가 너무 적음 — 저장하지 않음")
out = pathlib.Path(__file__).resolve().parent.parent / "assets" / "dur_dose.json"
out.write_text(json.dumps({"dose": dose, "period": period}, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
               encoding="utf-8")
print("저장:", out, out.stat().st_size, "bytes")
