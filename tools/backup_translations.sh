#!/bin/bash
# 備份翻譯原始檔到 iCloud Drive。
#
# 為什麼需要這支腳本：譯文與人工校對意見因為著作權考量被 .gitignore 排除
# （見 README「卡片資料」），所以它們不在任何 repo 裡，只存在這台電腦上。
# 卡表本身壞了還能從資料 repo 拿回來，但譯文重做要花上幾十小時。
#
#   ./tools/backup_translations.sh          # 備份到 iCloud Drive
#   ./tools/backup_translations.sh /path    # 備份到指定位置（外接硬碟等）
#
# 產生的是加日期的壓縮檔而不是直接覆蓋——同步式備份的問題是，
# 檔案壞掉之後那個「壞掉」也會被同步過去，舊快照才救得回來。

set -euo pipefail
cd "$(dirname "$0")/.."

DEST="${1:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/WSDeckBuilder-backup}"
STAMP="$(date +%Y%m%d-%H%M)"
ARCHIVE="$DEST/translations-$STAMP.tar.gz"
KEEP=10          # 保留最近幾份

mkdir -p "$DEST"

# tools/translations  人工譯文（卡名＋能力文字），無法再生
# tools/review_result.json  人工校對意見
# tools/sets/*_raw.json     官網原始資料；理論上可重抓，但官網改版就回不去了
tar -czf "$ARCHIVE" \
    tools/translations \
    tools/review_result.json \
    tools/sets/*_raw.json

SIZE="$(du -h "$ARCHIVE" | cut -f1)"
echo "已備份 → $ARCHIVE（$SIZE）"

# 驗證：壓縮檔列得出內容才算數，不然備份了個空殼也不知道
COUNT="$(tar -tzf "$ARCHIVE" | wc -l | tr -d ' ')"
echo "  內含 $COUNT 個項目，壓縮檔可正常讀取"

# 只留最近幾份，其餘刪掉
cd "$DEST"
ls -t translations-*.tar.gz 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
    rm -- "$old"
    echo "  清掉舊備份：$old"
done

TOTAL="$(ls -1 translations-*.tar.gz 2>/dev/null | wc -l | tr -d ' ')"
echo "  目前保留 $TOTAL 份（上限 $KEEP）"
