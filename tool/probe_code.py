import json, os, urllib.request, urllib.parse
U = "https://www.silson24.or.kr/cmm/api/v2/claim/getSearchHospitalsLocation"
def s24(kw, t="pharmacy", limit=200):
    b = {"keyword": kw, "servicedOnly": False, "hospitalType": t, "offset": {"offset": 0, "limit": limit}, "isCurrentLocation": False}
    r = urllib.request.Request(U, data=json.dumps(b).encode(), headers={"Content-Type": "application/json"}, method="POST")
    d = json.loads(urllib.request.urlopen(r, timeout=20).read())
    return d.get("result") or []
key = os.environ.get("DUR_API_KEY", "")
def hira(name, rows=100, extra=None):
    q = {"serviceKey": key, "_type": "json", "numOfRows": rows, "yadmNm": name}
    q.update(extra or {})
    d = json.loads(urllib.request.urlopen("https://apis.data.go.kr/B551182/pharmacyInfoService/getParmacyBasisList?" + urllib.parse.urlencode(q), timeout=20).read())
    b = d["response"]["body"]; it = b["items"]
    it = it.get("item", []) if isinstance(it, dict) else []
    it = it if isinstance(it, list) else [it]
    return b.get("totalCount"), it
s = s24("유명약국")
exact = [x for x in s if x["insttNm"].replace(" ", "") == "유명약국"]
print("S24 total", len(s), "exact", len(exact))
for x in exact[:40]:
    print(" S24", x["insttNm"], x["serviceEnabled"], x["hospitalCd"][:12], x["rnAddr"])
tot, h = hira("유명약국")
ex = [x for x in h if x["yadmNm"].replace(" ", "") == "유명약국"]
print("HIRA total", tot, "returned", len(h), "exact", len(ex))
for x in ex[:40]:
    print(" HIRA", x["yadmNm"], x["ykiho"][:12], x["addr"])
# 이름+좌표+반경 같이 되는지
tot2, h2 = hira("유명약국", 20, {"xPos": "127.0276", "yPos": "37.4979", "radius": "3000"})
print("HIRA near total", tot2, [(x["yadmNm"], x.get("distance"), x["addr"]) for x in h2][:5])
# 주소 대조
ak = lambda a: a.split("(")[0].split(",")[0].replace(" ", "")
s24keys = {ak(x["rnAddr"]): x for x in exact}
hit = [(x["addr"], s24keys[ak(x["addr"])]["serviceEnabled"]) for x in ex if ak(x["addr"]) in s24keys]
print("ADDR MATCH", len(hit), "of", len(ex)); print(hit[:10])
miss = [x["addr"] for x in ex if ak(x["addr"]) not in s24keys]
print("ADDR MISS sample", miss[:10])
print("S24 keys sample", list(s24keys)[:10])
