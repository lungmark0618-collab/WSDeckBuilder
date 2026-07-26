#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fetch_cards.py — 階段一 M1：抓取 ws-tcg 官網卡表 → raw_cards.json

M0 驗證結果（2026-07-26）：
  - 卡表查詢 API：GET https://ws-tcg.com/manage/CardListUser/searchJson
    參數同官網搜尋表單 query string（keyword / keyword_type[] / show_page_count / page）
  - 回傳 JSON：{items, total, page, limit, page_count}
  - 卡圖網址 = https://ws-tcg.com/wordpress/wp-content/images/cardlist/ + item["picture"]
  - 必須設定瀏覽器 User-Agent，否則 404

用法：
  python3 fetch_cards.py            # 抓 BRD/W139 全部卡片 → raw_cards.json
  python3 fetch_cards.py --set NIK/S117 --out raw_nik.json
"""
import argparse
import json
import re
import sys
import time
import urllib.parse
import urllib.request

API = "https://ws-tcg.com/manage/CardListUser/searchJson"
IMAGE_BASE = "https://ws-tcg.com/wordpress/wp-content/images/cardlist/"
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36")
REQUEST_INTERVAL = 1.5  # 秒，爬蟲禮儀（§3.1）

# card_kind 代碼（自 jquery.cards.js 確認：2=キャラ 3=イベント 4=クライマックス）
CARD_KIND = {"2": "character", "3": "event", "4": "climax"}

COLOR = {"yellow": "yellow", "green": "green", "red": "red", "blue": "blue"}

# 觸發圖標 gif 名 → 內部代碼（§3.4）。focus=チョイス(選)、salvage=カムバック(扉)
TRIGGER_GIF = {
    "soul": "soul", "gate": "gate", "treasure": "treasure",
    "salvage": "comeback", "draw": "draw", "pool": "pool",
    "shot": "shot", "standby": "standby", "choice": "choice",
    "focus": "choice", "bounce": "comeback",
}

GIF_TOKEN = re.compile(r"\[\[([a-z0-9_]+)\.gif\]\]")
# 平行卡卡號 = 基礎卡號 + 結尾大寫字母綴（-075S / -075SSP / -101a 等）
BASE_ID = re.compile(r"^(?P<base>.+?-(?:[A-Z]*)?\d+)(?P<suffix>[A-Za-z]*)$")


def http_get_json(url: str, params: dict):
    qs = urllib.parse.urlencode(params, doseq=True)
    req = urllib.request.Request(f"{url}?{qs}", headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_all_items(set_keyword: str):
    """依卡號關鍵字抓取全部分頁的原始 item。"""
    items, page, page_count = [], 1, 1
    while page <= page_count:
        data = http_get_json(API, {
            "keyword": set_keyword,
            "keyword_type[]": "no",       # 只比對卡號
            "show_page_count": 120,
            "page": page,
        })
        page_count = int(data.get("page_count") or 1)
        items.extend(data.get("items") or [])
        print(f"  第 {page}/{page_count} 頁：{len(data.get('items') or [])} 筆"
              f"（累計 {len(items)}/{data.get('total')}）", file=sys.stderr)
        page += 1
        if page <= page_count:
            time.sleep(REQUEST_INTERVAL)
    return items


def parse_trigger(raw: str):
    """'[[soul.gif]][[gate.gif]]' → 'gate'；雙魂 → 'soul2'；'-' → None"""
    gifs = GIF_TOKEN.findall(raw or "")
    if not gifs:
        return None
    codes = [TRIGGER_GIF.get(g) for g in gifs if TRIGGER_GIF.get(g)]
    if codes.count("soul") >= 2:
        return "soul2"
    non_soul = [c for c in codes if c != "soul"]
    if non_soul:
        return non_soul[0]
    return "soul" if codes else None


def parse_color(raw: str):
    m = GIF_TOKEN.search(raw or "")
    return COLOR.get(m.group(1)) if m else None


def parse_int(raw):
    s = str(raw or "").strip()
    return int(s) if s.lstrip("-").isdigit() and s != "-" else None


def parse_soul(raw):
    """魂傷欄位是圖示標記：'[[soul.gif]]'=1、兩個=2；事件/CX 為 '-'。"""
    s = str(raw or "").strip()
    count = s.count("[[soul.gif]]")
    if count:
        return count
    return parse_int(s)


ICON_LABEL = {  # 能力文字內嵌圖標 → 文字標記（翻譯前先固定化）
    "soul": "【魂】", "gate": "【門】", "treasure": "【寶】",
    "salvage": "【扉】", "draw": "【本】", "pool": "【金】",
    "shot": "【槍】", "standby": "【待】", "choice": "【選】", "focus": "【選】",
    "counter": "【反擊】", "clock": "【傷害區】", "stock": "【能量區】",
    "stand": "【直立】", "rest": "【橫置】", "backup": "【後援】",
    "trigger": "【判定】", "soul2": "【雙魂】", "bounce": "【扉】",
}


def clean_text(raw: str):
    """<br> → 換行；[[x.gif]] → 【…】文字標記。"""
    if not raw or raw.strip() == "-":
        return ""
    t = re.sub(r"<br\s*/?>", "\n", raw)
    t = GIF_TOKEN.sub(lambda m: ICON_LABEL.get(m.group(1), f"[{m.group(1)}]"), t)
    t = re.sub(r"<[^>]+>", "", t)  # 移除其餘 HTML 標籤
    return t.strip()


def base_card_id(card_number: str):
    m = BASE_ID.match(card_number.strip())
    if not m:
        return card_number.strip(), ""
    return m.group("base"), m.group("suffix")


def group_cards(items, source_rule):
    """依基礎卡號歸戶：一卡多刷（§3.2）。"""
    groups = {}
    order = []
    for it in items:
        num = it["card_number"].strip()
        base, suffix = base_card_id(num)
        printing = {
            "id": num,
            "rarity": (it.get("rare") or "").strip(),
            "image_url": IMAGE_BASE + it["picture"].strip(),
            "is_foil": bool(suffix) or (it.get("parallel_param") or "").strip() != "",
        }
        if base not in groups:
            order.append(base)
            traits = [t for t in (it.get(f"feature{i}") or "" for i in (1, 2, 3))
                      if t.strip() and t.strip() != "-"]
            text = clean_text(it.get("text") or "")
            groups[base] = {
                "id": base,
                "printings": [],
                "name_jp": (it.get("card_name") or "").strip(),
                "card_type": CARD_KIND.get(str(it.get("card_kind")), "character"),
                "color": parse_color(it.get("color") or ""),
                "level": parse_int(it.get("level")),
                "cost": parse_int(it.get("cost")),
                "power": parse_int(it.get("power")),
                "soul": parse_soul(it.get("soul")),
                "trigger": parse_trigger(it.get("card_trigger") or ""),
                "traits_jp": [t.strip() for t in traits],
                "text_jp": text,
                "text_lines_jp": [ln for ln in text.split("\n") if ln.strip()],
                "source": source_rule(base),
            }
        groups[base]["printings"].append(printing)

    # 普卡（無字綴）排在 printings[0]，其餘依卡號排序
    for base in order:
        groups[base]["printings"].sort(
            key=lambda p: (p["id"] != base, len(p["id"]), p["id"]))
    return [groups[b] for b in order]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", default="BRD/W139", help="卡號前綴，如 BRD/W139")
    ap.add_argument("--out", default="raw_cards.json")
    args = ap.parse_args()

    print(f"抓取 {args.set} …", file=sys.stderr)
    items = fetch_all_items(args.set)
    # 只保留卡號確實以目標前綴開頭的（keyword 搜尋可能誤中）
    items = [it for it in items if it["card_number"].startswith(args.set)]

    def source_rule(base_id: str):
        # 預組卡號慣例含 T（如 -T01）；PR 卡以稀有度判斷
        num_part = base_id.split("-")[-1]
        return "trial_deck" if num_part.upper().startswith("T") else "booster"

    cards = group_cards(items, source_rule)
    out = {
        "meta": {
            "title_code": args.set,
            "title_name_jp": "ブラウンダスト2",
            "title_name_zh": "棕色塵埃2",
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S+08:00"),
            "schema_version": 1,
            "card_count": len(cards),
            "printing_count": sum(len(c["printings"]) for c in cards),
        },
        "cards": cards,
    }
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"完成：{len(cards)} 張唯一卡片 / "
          f"{out['meta']['printing_count']} 個刷版 → {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
