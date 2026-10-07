"""실손24 참여병원 검색 페이지가 쓰는 요청(주소·파라미터·응답 형태)을 기록한다. 진단용."""
import asyncio
import json

from playwright.async_api import async_playwright

URL = "https://www.silson24.or.kr/claim/web/serviceHospitalList"
QUERY = "서울아산병원"


async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch()
        page = await b.new_page(locale="ko-KR")
        seen = []

        async def on_response(resp):
            req = resp.request
            if req.resource_type in ("xhr", "fetch") or "json" in (resp.headers.get("content-type") or ""):
                try:
                    body = await resp.text()
                except Exception as e:  # noqa: BLE001
                    body = f"<{e}>"
                seen.append({
                    "method": req.method,
                    "url": req.url,
                    "post": (req.post_data or "")[:500],
                    "status": resp.status,
                    "ctype": resp.headers.get("content-type"),
                    "body": body[:1500],
                })

        page.on("response", on_response)
        await page.goto(URL, wait_until="networkidle", timeout=60000)
        print("TITLE", await page.title())
        # 화면의 입력창·버튼 목록
        inputs = await page.eval_on_selector_all(
            "input,select,button",
            "els => els.map(e => ({tag:e.tagName, id:e.id, name:e.name, type:e.type, ph:e.placeholder, text:(e.innerText||'').slice(0,30), cls:e.className}))",
        )
        print("CONTROLS", json.dumps(inputs, ensure_ascii=False)[:4000])
        # 기관명 입력창을 찾아 검색
        box = None
        for sel in ["input[placeholder*='기관']", "input[placeholder*='병원']", "input[placeholder*='검색']",
                    "input[type='text']", "input[type='search']"]:
            if await page.locator(sel).count():
                box = page.locator(sel).first
                print("INPUT", sel)
                break
        if box:
            await box.fill(QUERY)
            await box.press("Enter")
            await page.wait_for_timeout(3000)
            for sel in ["button:has-text('검색')", "a:has-text('검색')", ".btn_search", "#btnSearch"]:
                if await page.locator(sel).count():
                    try:
                        await page.locator(sel).first.click()
                        print("CLICK", sel)
                        break
                    except Exception as e:  # noqa: BLE001
                        print("CLICKFAIL", sel, e)
            await page.wait_for_timeout(4000)
        text = await page.inner_text("body")
        print("BODY_TEXT", " ".join(text.split())[:3000])
        for s in seen:
            print("REQ", json.dumps(s, ensure_ascii=False))
        await b.close()


asyncio.run(main())
