#!/bin/bash
# 備份翻譯原始檔到 iCloud Drive。
#
# 為什麼需要這支腳本：譯文與人工校對意見因為著作權考量被 .gitignore 排除
# （見 README「卡片資料」），所以它們不在任何 repo 裡，只存在這台電腦上。
# 卡表本身壞了還能從資料 repo 拿回來，但譯文重做要花上幾十小時。
#
#   ./tools/backup_translations.sh              # iCloud + 本機各存一份
#   ./tools/backup_translations.sh /Volumes/X   # 只存到指定位置（外接硬碟等）
#
# 預設同時寫兩個地方，因為兩者擋的是不同的意外：
#   iCloud     — 電腦壞掉、遺失
#   ~/Backups  — iCloud 帳號出事、誤刪同步、「最佳化儲存空間」把檔案清成雲端指標
# 注意這台機器的「桌面」與「文件」都被 iCloud 接管了，存那裡不算本機備份。
#
# 產生的是加日期的壓縮檔而不是直接覆蓋——同步式備份的問題是，
# 檔案壞掉之後那個「壞掉」也會被同步過去，舊快照才救得回來。

set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -gt 0 ]; then
    DESTS=("$@")
else
    DESTS=(
        "$HOME/Library/Mobile Documents/com~apple~CloudDocs/WSDeckBuilder-backup"
        "$HOME/Backups/WSDeckBuilder"
    )
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

for DEST in "${DESTS[@]}"; do
    mkdir -p "$DEST"
    cp "$ARCHIVE" "$DEST/"
    # 複製過去也要能讀，才算真的到位
    if tar -tzf "$DEST/translations-$STAMP.tar.gz" >/dev/null 2>&1; then
        echo "  ✓ $DEST"
    else
        echo "  ✗ $DEST（複製後讀不開）" >&2
        exit 1
    fi
    # 只留最近幾份，其餘刪掉
    ( cd "$DEST" && ls -t translations-*.tar.gz 2>/dev/null \
        | tail -n +$((KEEP + 1)) | while read -r old; do rm -- "$old"; done )
    N="$(ls -1 "$DEST"/translations-*.tar.gz 2>/dev/null | wc -l | tr -d ' ')"
    echo "    保留 $N 份（上限 $KEEP）"
done
