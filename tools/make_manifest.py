#!/usr/bin/env python3
"""從卡表產生 manifest.json（§4.4.8 的線上更新目錄）。

App 會下載這個 manifest，逐部作品比對 data_version，只抓有變動的那幾份。
translate.py 每重新產出一份卡表就會把該作品的 data_version +1，所以這支
腳本只要照著讀出來就好，不需要自己記版本。

用法：

    # 把 Resources/ 底下的卡表整理成一份 manifest
    python3 tools/make_manifest.py \\
        --base-url https://example.com/wsdeck/ \\
        --notes "新增 BD/W54 第二波簽卡；修正泰蕾莎能力錯字" \\
        --out dist/manifest.json

    # 同時把要上傳的卡表複製到 dist/
    python3 tools/make_manifest.py ... --copy

發佈流程：把 dist/ 底下的檔案上傳到你的靜態空間，App 下次檢查就會拿到。
"""

import argparse
import glob
import json
import os
import shutil
import sys
import time
from urllib.parse import urljoin

# App 端的 DataUpdater.supportedSchemaVersion，改格式時兩邊要一起動
SCHEMA_VERSION = 1

DEFAULT_RESOURCES = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "WSDeckBuilder", "Resources")


def main():
    parser = argparse.ArgumentParser(
        description="產生卡表線上更新用的 manifest.json")
    parser.add_argument("--resources", default=DEFAULT_RESOURCES,
                        help="卡表所在目錄（預設為 App 的 Resources/）")
    parser.add_argument("--base-url", required=True,
                        help="卡表上傳後的目錄網址，例如 https://example.com/wsdeck/")
    parser.add_argument("--notes", default="",
                        help="這次更新的說明，會顯示在 App 的設定頁")
    parser.add_argument("--out", default="dist/manifest.json")
    parser.add_argument("--copy", action="store_true",
                        help="順便把卡表複製到 manifest 所在目錄")
    args = parser.parse_args()

    # base-url 少了結尾斜線，urljoin 會把最後一段路徑吃掉
    base = args.base_url if args.base_url.endswith("/") else args.base_url + "/"

    paths = sorted(glob.glob(os.path.join(args.resources, "*_cards.json")))
    if not paths:
        sys.exit(f"在 {args.resources} 找不到任何 *_cards.json")

    sets = []
    for path in paths:
        name = os.path.basename(path)
        try:
            with open(path, encoding="utf-8") as f:
                meta = json.load(f)["meta"]
        except (ValueError, KeyError, OSError) as exc:
            sys.exit(f"{name} 讀取失敗：{exc}")
        version = meta.get("data_version", 1)
        sets.append({
            "title_code": meta["title_code"],
            "file": name,
            "data_version": version,
            "url": urljoin(base, name),
        })
        print(f"  {meta['title_code']:<10} v{version}  {name}", file=sys.stderr)

    manifest = {
        "schema_version": SCHEMA_VERSION,
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S+08:00"),
        "notes": args.notes,
        "sets": sets,
    }

    out_dir = os.path.dirname(os.path.abspath(args.out))
    os.makedirs(out_dir, exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    print(f"\n{len(sets)} 部作品 → {args.out}", file=sys.stderr)

    if args.copy:
        for path in paths:
            shutil.copy2(path, os.path.join(out_dir, os.path.basename(path)))
        print(f"卡表已複製到 {out_dir}/", file=sys.stderr)

    print("上傳這個目錄的內容即可；App 下次檢查就會拿到。", file=sys.stderr)


if __name__ == "__main__":
    main()
