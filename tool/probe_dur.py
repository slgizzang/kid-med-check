import json, os, urllib.parse, urllib.request
key = os.environ["DUR_API_KEY"]
base = "https://apis.data.go.kr/1471000/DURIrdntInfoService03/"
ops = ["getCpctyAtentInfoList03", "getMdctnPdAtentInfoList03"]
for op in ops:
    for name in ["아세트아미노펜", "메토클로프라미드", ""]:
        q = {"serviceKey": key, "type": "json", "numOfRows": 2, "pageNo": 1}
        if name:
            q["ingrKorName"] = name
        try:
            raw = urllib.request.urlopen(base + op + "?" + urllib.parse.urlencode(q), timeout=20).read()
            try:
                d = json.loads(raw)
            except Exception:
                print(f"== {op} [{name}] raw", raw[:400]); continue
            b = d.get("body") or d.get("response", {}).get("body", {})
            items = b.get("items") or []
            if isinstance(items, dict):
                items = items.get("item", [])
            if isinstance(items, dict):
                items = [items]
            print(f"== {op} [{name}] total={b.get('totalCount')}")
            for it in items[:2]:
                it = it.get("item", it)
                print("  ", json.dumps(it, ensure_ascii=False, indent=1))
        except Exception as e:
            print(f"== {op} [{name}] fail {e}")
