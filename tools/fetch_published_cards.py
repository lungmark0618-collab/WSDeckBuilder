#!/usr/bin/env python3
"""從已發佈的 manifest 下載卡表，填進 App 的 Resources/。

這個 repo 不含卡片資料（著作權考量，見 README），但 App 沒有卡表就跑不起來，
測試也有 9 項會失敗。要自己從官網重建得花上一小時，所以這裡提供一條快路：
直接抓 App 平常在抓的那份線上卡表。

    python3 tools/fetch_published_cards.py                    # → WSDeckBuilder/Resources/
    python3 tools/fetch_published_cards.py --out /tmp/cards    # 抓到別處

抓下來的每一份都會驗證：解得開、title_code 對得上 manifest、卡片陣列非空。
這和 App 端 DataUpdater 落地前做的檢查是同一組。
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

# 與 DataUpdater.manifestURL 指向同一處。改發佈位置時兩邊要一起改。
MANIFEST_URL = ("https://raw.githubusercontent.com/lungmark0618-collab"
                "/WSDeckBuilder-data/main/manifest.json")

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(os.path.dirname(HERE), "WSDeckBuilder", "Resources")


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "WSDeckBuilder-fetch"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def main():
    ap = argparse.ArgumentParser(description="下載已發佈的卡表")
    ap.add_argument("--manifest", default=MANIFEST_URL)
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()

    try:
        manifest = json.loads(get(args.manifest))
    except (urllib.error.URLError, ValueError) as exc:
        sys.exit(f"讀不到 manifest（{args.manifest}）：{exc}")

    sets = manifest.get("sets") or []
    if not sets:
        sys.exit("manifest 裡沒有任何作品")

    os.makedirs(args.out, exist_ok=True)
    total = 0
    for entry in sets:
        name = entry.get("file", "")
        if not name.endswith("_cards.json"):
            print(f"  跳過 {name!r}（檔名不符）", file=sys.stderr)
            continue
        try:
            raw = get(entry["url"])
            data = json.loads(raw)
        except (urllib.error.URLError, ValueError, KeyError) as exc:
            sys.exit(f"{name} 下載或解析失敗：{exc}")

        meta = data.get("meta", {})
        # 和 App 端落地前一樣的三道檢查，免得抓到擺錯的檔案
        if meta.get("title_code") != entry.get("title_code"):
            sys.exit(f"{name} 的作品代號對不上"
                     f"（manifest {entry.get('title_code')}，檔案 {meta.get('title_code')}）")
        if not data.get("cards"):
            sys.exit(f"{name} 沒有任何卡片")

        with open(os.path.join(args.out, name), "wb") as f:
            f.write(raw)
        n = len(data["cards"])
        total += n
        print(f"  {meta.get('title_code', '?'):<10} v{meta.get('data_version', '?')}  {n} 張")

    print(f"\n{len(sets)} 部作品、共 {total} 張卡 → {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
