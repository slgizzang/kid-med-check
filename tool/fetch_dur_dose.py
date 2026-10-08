"""식약처 DUR 성분정보의 용량주의(1일 최대 투여량)·투여기간주의(최대 투여기간) 전체 목록을
assets/dur_dose.json 으로 저장한다. 표가 작아서(수백 건) 앱에 통째로 넣는다.

품목 API(DURPrdlstInfoService03)에는 최대량·최대기간 값이 없고, 성분 API에만 있다.
"""
import json, os, pathlib, sys, time, urllib.parse, urllib.request

key = os.environ.get("DUR_API_KEY", "")
if not key:
    sys.exit("DUR_API_KEY 없음")
base = "https://apis.data.go.kr/1471000/DURIrdntInfoService03/"
KEEP = ["MIX_TYPE", "INGR_CODE", "INGR_NAME", "INGR_ENG_NAME", "MIX_INGR", "ORI_INGR",
        "CLASS_NAME", "FORM_NAME", "PROHBT_CONTENT", "REMARK"]


def fetch(op, value_key):
    out, page = [], 1
    while True:
        q = {"serviceKey": key, "type": "json", "numOfRows": 100, "pageNo": page}
        for attempt in range(3):
            try:
                d = json.loads(urllib.request.urlopen(base + op + "?" + urllib.parse.urlencode(q), timeout=30).read())
                break
            except Exception as e:
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
            if (it.get("DEL_YN") or "정상") != "정상":
                continue
            row = {k: (it.get(k) or "").strip() for k in KEEP if (it.get(k) or "").strip()}
            row["max"] = (it.get(value_key) or "").strip()
            out.append(row)
        total = int(b.get("totalCount") or 0)
        if page * 100 >= total or not items:
            break
        page += 1
    return out, total


dose, t1 = fetch("getCpctyAtentInfoList02", "MAX_QTY")
period, t2 = fetch("getMdctnPdAtentInfoList02", "MAX_DOSAGE_TERM")
print(f"용량주의 {len(dose)}/{t1}, 투여기간주의 {len(period)}/{t2}")
if len(dose) < 100 or len(period) < 20:
    sys.exit("받은 건수가 너무 적음 — 저장하지 않음")
for name, rows in [("용량", dose), ("기간", period)]:
    print(name, "max 예:", sorted({r["max"] for r in rows})[:60])
    print(name, "복합 예:", [r for r in rows if r.get("MIX_TYPE") != "단일"][:3])
out = pathlib.Path(__file__).resolve().parent.parent / "assets" / "dur_dose.json"
out.write_text(json.dumps({"dose": dose, "period": period}, ensure_ascii=False, separators=(",", ":")),
               encoding="utf-8")
print("저장:", out, out.stat().st_size, "bytes")
