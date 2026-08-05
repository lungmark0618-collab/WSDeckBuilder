#!/bin/bash
# 備份翻譯原始檔到 iCloud Drive。
#
# 為什麼需要這支腳本：譯文與人工校對意見因為著作權考量被 .gitignore 排除
# （見 README「卡片資料」），所以它們不在任何 repo 裡，只存在這台電腦上。
# 卡表本身壞了還能從資料 repo 拿回來，但譯文重做要花上幾十小時。
#
#   ./tools/backup_translations.sh              # iCloud + 本機各存一份
#   ./tools/backup_translations.sh /Volumes/X   # 只存到指定位置（外接硬碟等）
#   ./tools/backup_translations.sh --max-age 7  # 最近 7 天內備過就跳過
#
# --max-age 是給排程用的。排程只保證「時間到了會跑」，不保證電腦當下開著；
# 所以改成排程與登入各觸發一次，由腳本自己看上次備份多久以前來決定要不要做。
# 錯過的那一週會在下次開機時補上，而且不會因為多觸發幾次就備出一堆重複檔。
#
# 預設同時寫兩個地方，因為兩者擋的是不同的意外：
#   iCloud     — 電腦壞掉、遺失
#   ~/Backups  — iCloud 帳號出事、誤刪同步、「最佳化儲存空間」把檔案清成雲端指標
# 注意這台機器的「桌面」與「文件」都被 iCloud 接管了，存那裡不算本機備份。
#
# ⚠️ 排程（launchd）跑的時候只能指定 ~/Backups。macOS 的隱私保護不讓背景工作碰
#    iCloud Drive，連列目錄都會被拒——而列不到目錄，--max-age 就會誤判成「沒備過」
#    而每次都重備。iCloud 那份靠手動執行時更新（終端機有權限）。
#
# 產生的是加日期的壓縮檔而不是直接覆蓋——同步式備份的問題是，
# 檔案壞掉之後那個「壞掉」也會被同步過去，舊快照才救得回來。

set -euo pipefail
cd "$(dirname "$0")/.."

MAX_AGE=""
if [ "${1:-}" = "--max-age" ]; then
    MAX_AGE="$2"; shift 2
fi

if [ $# -gt 0 ]; then
    DESTS=("$@")
else
    DESTS=(
        "$HOME/Library/Mobile Documents/com~apple~CloudDocs/WSDeckBuilder-backup"
        "$HOME/Backups/WSDeckBuilder"
    )
fi

# 以「最舊的那個目的地」為準：只要有一邊過期就重備，不然那一邊會永遠落後
if [ -n "$MAX_AGE" ]; then
    STALE=0
    for DEST in "${DESTS[@]}"; do
        NEWEST="$(ls -t "$DEST"/translations-*.tar.gz 2>/dev/null | head -1 || true)"
        if [ -z "$NEWEST" ]; then STALE=1; break; fi
        # find -mtime 用天數比對，+N 表示「超過 N 天」
        if [ -n "$(find "$NEWEST" -mtime "+$MAX_AGE" 2>/dev/null)" ]; then STALE=1; break; fi
    done
    if [ "$STALE" -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M') 最近 $MAX_AGE 天內已備份，跳過"
        exit 0
    fi
fi

STAMP="$(date +%Y%m%d-%H%M)"
KEEP=10          # 每個位置保留最近幾份
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ARCHIVE="$STAGE/translations-$STAMP.tar.gz"

# tools/translations  人工譯文（卡名＋能力文字），無法再生
# tools/review_result.json  人工校對意見
# tools/sets/*_raw.json     官網原始資料；理論上可重抓，但官網改版就回不去了
tar -czf "$ARCHIVE" \
    tools/translations \
    tools/review_result.json \
    tools/sets/*_raw.json

# 驗證：壓縮檔列得出內容才算數，不然備份了個空殼也不知道
COUNT="$(tar -tzf "$ARCHIVE" | wc -l | tr -d ' ')"
SIZE="$(du -h "$ARCHIVE" | cut -f1)"
echo "打包完成：$COUNT 個項目，$SIZE"

# 每個目的地各自獨立處理：一個掛掉不該讓其他的也沒備到。
# （這是實際踩過的坑——iCloud 那邊失敗時，整個腳本就中止，本機那份從此再也沒更新。）
FAILED=0
for DEST in "${DESTS[@]}"; do
    if ! mkdir -p "$DEST" 2>/dev/null || ! cp "$ARCHIVE" "$DEST/" 2>/dev/null; then
        echo "  ✗ $DEST（寫入失敗）" >&2
        FAILED=1
        continue
    fi
    # 複製過去也要能讀，才算真的到位
    if ! tar -tzf "$DEST/translations-$STAMP.tar.gz" >/dev/null 2>&1; then
        echo "  ✗ $DEST（複製後讀不開）" >&2
        FAILED=1
        continue
    fi
    echo "  ✓ $DEST"
    # 只留最近幾份，其餘刪掉。清不掉不算失敗，備份本身已經成功了
    ( cd "$DEST" 2>/dev/null && ls -t translations-*.tar.gz 2>/dev/null \
        | tail -n +$((KEEP + 1)) | while read -r old; do rm -- "$old"; done ) || true
    N="$(ls -1 "$DEST"/translations-*.tar.gz 2>/dev/null | wc -l | tr -d ' ')"
    echo "    保留 ${N:-?} 份（上限 $KEEP）"
done

exit $FAILED
