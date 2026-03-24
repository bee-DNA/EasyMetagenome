#!/bin/bash

# ==========================================
# setup_eggnog_env.sh
# 建立 eggNOG-mapper 環境與下載資料庫
# 執行前請確認至少有 50GB 硬碟空間
# ==========================================

set -u

# ==========================================
# 配置
# ==========================================

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
soft=~/miniconda3
db=~/db/eggnog
EGGNOG_ENV="eggnog_env"
LOG_FILE="${WORK_DIR}/setup_eggnog_$(date +%Y%m%d_%H%M%S).log"

# ==========================================
# 準備階段
# ==========================================

echo "=========================================="
echo "eggNOG-mapper 環境建置與資料庫下載"
echo "Log 檔案: $LOG_FILE"
echo "⚠ 注意：資料庫下載需要約 40~50GB 的硬碟空間"
echo "=========================================="
echo ""

# 檢查 conda
if [ -f "${soft}/etc/profile.d/conda.sh" ]; then
    source "${soft}/etc/profile.d/conda.sh"
else
    echo "❌ 找不到 conda: ${soft}/etc/profile.d/conda.sh" | tee -a "$LOG_FILE"
    exit 1
fi

# ==========================================
# 建立環境
# ==========================================

echo "[1/3] 檢查與建立 conda 環境 ($EGGNOG_ENV)..." | tee -a "$LOG_FILE"

if conda env list | grep -q "^${EGGNOG_ENV} "; then
    echo "  ✓ conda 環境已存在" | tee -a "$LOG_FILE"
else
    echo "  >> 開始建立環境 (時間較長，請耐心等候)..." | tee -a "$LOG_FILE"
    if conda create -n "$EGGNOG_ENV" python=3.10 -y >>"$LOG_FILE" 2>&1; then
        echo "  ✓ 環境建立成功" | tee -a "$LOG_FILE"
    else
        echo "  ❌ 環境建立失敗，請查看 log" | tee -a "$LOG_FILE"
        exit 1
    fi
fi

# 進入環境
conda activate "$EGGNOG_ENV"

# ==========================================
# 安裝程式
# ==========================================

echo "[2/3] 安裝 eggNOG-mapper 套件..." | tee -a "$LOG_FILE"

if ! command -v emapper.py &>/dev/null; then
    echo "  >> 開始安裝 eggnog-mapper..." | tee -a "$LOG_FILE"
    if conda install -c bioconda eggnog-mapper -y >>"$LOG_FILE" 2>&1; then
        echo "  ✓ eggnog-mapper 安裝成功" | tee -a "$LOG_FILE"
    else
        echo "  ❌ 套件安裝失敗，請查看 log" | tee -a "$LOG_FILE"
        exit 1
    fi
else
    echo "  ✓ eggnog-mapper 已安裝" | tee -a "$LOG_FILE"
fi

# ==========================================
# 下載資料庫
# ==========================================

echo "[3/3] 下載功能註釋資料庫 (需 40~50GB 空間，耗時較長)..." | tee -a "$LOG_FILE"

mkdir -p "$db"

if [ -f "$db/eggnog.db" ] && [ -f "$db/eggnog_proteins.dmnd" ]; then
    echo "  ✓ 資料庫已存在 ($db/eggnog.db 等檔案)" | tee -a "$LOG_FILE"
else
    echo "  >> 開始下載基礎資料庫..." | tee -a "$LOG_FILE"
    # -y 自動同意, --data_dir 指定路徑
    if download_eggnog_data.py -y --data_dir "$db" 2>&1 | tee -a "$LOG_FILE"; then
        echo "  ✓ 基礎資料庫下載完成" | tee -a "$LOG_FILE"
    else
        echo "  ❌ 資料庫下載過程中發生錯誤，請查看 log" | tee -a "$LOG_FILE"
        exit 1
    fi
fi

echo ""
echo "=========================================="
echo "✅ eggNOG-mapper 環境與資料庫已全部準備就緒！"
echo "您可以開始執行分析腳本: ./5_eggnog_analysis.sh"
echo "=========================================="
