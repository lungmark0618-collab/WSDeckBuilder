#!/usr/bin/env python3
"""印出一台可用的 iPhone 模擬器 UDID，供 xcodebuild -destination 使用。

CI 裡把裝置名稱寫死（`name=iPhone 16`）會在 runner 映像更新或 Apple 改名時
突然壞掉，而那種失敗看起來像測試爛了，很浪費時間。改成問系統現在有什麼。

    python3 tools/pick_simulator.py            # 只印 UDID
    python3 tools/pick_simulator.py --verbose  # 連裝置名一起印到 stderr
"""

import argparse
import json
import subprocess
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    out = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        capture_output=True, text=True, check=True).stdout
    devices = json.loads(out).get("devices", {})

    # runtime 字串形如 com.apple.CoreSimulator.SimRuntime.iOS-18-2，
    # 反向排序等於挑最新的 iOS
    for runtime, items in sorted(devices.items(), reverse=True):
        if "iOS" not in runtime:
            continue
        for d in items:
            if d.get("isAvailable") and "iPhone" in d.get("name", ""):
                if args.verbose:
                    print(f"{d['name']}（{runtime.rsplit('.', 1)[-1]}）", file=sys.stderr)
                print(d["udid"])
                return

    sys.exit("找不到可用的 iPhone 模擬器")


if __name__ == "__main__":
    main()
