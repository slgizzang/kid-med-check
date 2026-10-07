import json, os, urllib.request, urllib.parse
U = "https://www.silson24.or.kr/cmm/api/v2/claim/getSearchHospitalsLocation"
def s24(kw, t="hospital"):
    b = {"keyword": kw, "servicedOnly": False, "hospitalType": t, "offset": {"offset": 0, "limit": 10},
         "isCurrentLocation": False}
    r = urllib.request.Request(U, data=json.dumps(b).encode(), headers={"Content-Type": "application/json"}, method="POST")
    try:
        d = json.loads(urllib.request.urlopen(r, timeout=20).read())
        return [(x["insttNm"], x["hospitalCd"], x["serviceEnabled"], x["rnAddr"]) for x in d.get("result") or []]
    except Exception as e:
        return repr(e)[:200]
key = os.environ.get("DUR_API_KEY", "")
def hira(name, pharm=False):
    path = "B551182/pharmacyInfoService/getParmacyBasisList" if pharm else "B551182/hospInfoServicev2/getHospBasisList"
    q = urllib.parse.urlencode({"serviceKey": key, "_type": "json", "numOfRows": 5, "yadmNm": name})
    try:
        d = json.loads(urllib.request.urlopen(f"https://apis.data.go.kr/{path}?{q}", timeout=20).read())
        it = d["response"]["body"]["items"]
        it = it.get("item", []) if isinstance(it, dict) else []
        it = it if isinstance(it, list) else [it]
        return [(x.get("yadmNm"), x.get("ykiho"), x.get("addr")) for x in it]
    except Exception as e:
        return repr(e)[:200]
print("S24 name 아산", s24("서울아산병원"))
print("S24 partial 아산", s24("아산"))
print("S24 code 11100800", s24("11100800"))
print("S24 name 써니", s24("써니이비인후과"))
h = hira("서울아산병원"); print("HIRA 아산", h)
h2 = hira("써니이비인후과"); print("HIRA 써니", h2)
if isinstance(h2, list) and h2:
    print("S24 by ykiho 써니", s24(h2[0][1]))
print("HIRA 강동성심", hira("강동성심병원"))
print("S24 강동성심", s24("강동성심병원"))
print("HIRA 온누리 pharm", hira("온누리약국", True))
print("S24 온누리 pharm", s24("온누리약국", "pharmacy")[:5] if isinstance(s24("온누리약국", "pharmacy"), list) else "")
