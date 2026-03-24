#!/bin/bash

# ==========================================
# 1.5_checkm2_analysis.sh
# 基因組質量評估流程 (checkm2_env 環境)
# CheckM2 品質評估
# ==========================================

set -u

# ==========================================
# 配置
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-$SCRIPT_DIR}"
SEQ_DIR="${SEQ_DIR:-$WORK_DIR}"
RESULT_DIR="${RESULT_DIR:-$WORK_DIR/result}"
TEMP_DIR="${TEMP_DIR:-$WORK_DIR/temp}"
BIN_DIR="${RESULT_DIR}/bins"
CHECKM2_DIR="${RESULT_DIR}/checkm2"
LOG_DIR="${LOG_DIR:-$WORK_DIR/log}"
LOG_FILE="${LOG_DIR}/checkm2_$(date +%Y%m%d_%H%M%S).log"
CHECKM2_REPORT="${CHECKM2_DIR}/quality_report.tsv"

CONDA_BASE="${CONDA_BASE:-$HOME/miniconda3}"
DB_DIR="${DB_DIR:-$HOME/db}"
THREADS="${THREADS:-16}"
CHECKM2_ENV="checkm2_env"
USE_CONDA="${USE_CONDA:-auto}"

# ==========================================
# Log 函數
# ==========================================

log()      { echo "[$(date '+%H:%M:%S')] $*"    | tee -a "$LOG_FILE"; }
log_step() {
    echo ""                                       | tee -a "$LOG_FILE"
    echo "==========================================" | tee -a "$LOG_FILE"
    echo "[$(date '+%H:%M:%S')] $*"              | tee -a "$LOG_FILE"
    echo "==========================================" | tee -a "$LOG_FILE"
}
log_ok()   { echo "[$(date '+%H:%M:%S')] ✓ $*"  | tee -a "$LOG_FILE"; }
log_warn() { echo "[$(date '+%H:%M:%S')] ⚠ $*"  | tee -a "$LOG_FILE"; }
log_err()  { echo "[$(date '+%H:%M:%S')] ❌ $*" | tee -a "$LOG_FILE"; }

# ==========================================
# 開始
# ==========================================

mkdir -p "$LOG_DIR"

# 若已有既有報告，允許直接跳過（便於重跑後續模組與容器 smoke 測試）
if [ -f "$CHECKM2_REPORT" ] && [ -s "$CHECKM2_REPORT" ]; then
    echo "==========================================" | tee "$LOG_FILE"
    echo "基因組質量評估流程 (CheckM2)"                | tee -a "$LOG_FILE"
    echo "Log 檔案: $LOG_FILE"                       | tee -a "$LOG_FILE"
    echo "==========================================" | tee -a "$LOG_FILE"
    log_ok "CheckM2 結果已存在 ($CHECKM2_REPORT)，跳過本階段。"
    exit 0
fi

echo "==========================================" | tee "$LOG_FILE"
echo "基因組質量評估流程 (CheckM2)"                | tee -a "$LOG_FILE"
echo "Log 檔案: $LOG_FILE"                       | tee -a "$LOG_FILE"
echo "==========================================" | tee -a "$LOG_FILE"

log "工作目錄: $WORK_DIR"
log "資料庫目錄: $DB_DIR"
log "線程數: $THREADS"

# 激活 conda（可選）
if [ "$USE_CONDA" != "0" ]; then
    if [ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]; then
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        log "激活 $CHECKM2_ENV 環境..."
        if conda activate "$CHECKM2_ENV" 2>/dev/null; then
            log_ok "環境: $CHECKM2_ENV"
        elif [ "$USE_CONDA" = "1" ]; then
            log_err "找不到 conda 環境: $CHECKM2_ENV"
            log "請先建立環境："
            log "  conda create -n $CHECKM2_ENV python=3.8 -y"
            log "  conda activate $CHECKM2_ENV"
            log "  conda install -c bioconda -c conda-forge checkm2 -y"
            log "  checkm2 database --download --path $DB_DIR/checkm2"
            exit 1
        else
            log_warn "未啟用 conda 環境，改用當前 PATH 內工具"
        fi
    elif [ "$USE_CONDA" = "1" ]; then
        log_err "找不到 conda: ${CONDA_BASE}/etc/profile.d/conda.sh"
        exit 1
    else
        log_warn "找不到 conda，改用當前 PATH 內工具"
    fi
else
    log "USE_CONDA=0，跳過 conda 激活"
fi

# 檢查指令
if ! command -v checkm2 &>/dev/null; then
    log_err "CheckM2 未安裝。請在 $CHECKM2_ENV 環境中安裝。"
    exit 1
fi

# ==========================================
# 準備檔案
# ==========================================

log_step "準備 bins"

ALL_BINS_DIR="${BIN_DIR}/all_bins"

mkdir -p "$ALL_BINS_DIR" "$CHECKM2_DIR"

if [ ! -d "$BIN_DIR" ]; then
    log_err "找不到 bins 目錄: $BIN_DIR。請先執行 ./1_main_analysis.sh 完成 Binning 步驟。"
    exit 1
fi

# 收集所有 bins
log "收集 bins 到 $ALL_BINS_DIR..."
for sample_dir in "$BIN_DIR"/*/; do
    if [ -d "$sample_dir" ] && [ "$(basename "$sample_dir")" != "all_bins" ]; then
        cp "$sample_dir"/*.fa "$ALL_BINS_DIR/" 2>/dev/null || true
    fi
done

BIN_COUNT=$(ls "$ALL_BINS_DIR"/*.fa 2>/dev/null | wc -l || echo "0")
if [ "$BIN_COUNT" -eq 0 ]; then
    log_err "無 bins 可評估。看起來尚未產生任何 bins。"
    exit 1
fi
log_ok "找到 $BIN_COUNT 個 bins 準備評估。"

# ==========================================
# 執行 CheckM2
# ==========================================

log_step "基因組質量評估 (CheckM2)"

if [ -f "$CHECKM2_REPORT" ]; then
    log_ok "CheckM2 結果已存在 ($CHECKM2_REPORT)，跳過重新執行。"
else
    # 檢查資料庫
    if ! checkm2 database --info &>/dev/null 2>&1; then
        log_warn "CheckM2 資料庫未設定"
        log "如需手動下載: checkm2 database --download --path $DB_DIR/checkm2"
    fi

    log "執行 CheckM2 predict (可能需要數十分鐘到數小時)..."
    if checkm2 predict \
        --input "$ALL_BINS_DIR" \
        --output-directory "$CHECKM2_DIR" \
        --force \
        --extension fa \
        --threads "$THREADS" \
        >>"$LOG_FILE" 2>&1; then
        log_ok "CheckM2 執行完成"
    else
        log_err "CheckM2 執行失敗，請查看 log: $LOG_FILE"
        exit 1
    fi
fi

# ==========================================
# 輸出摘要
# ==========================================

log_step "評估摘要"

if [ -f "$CHECKM2_REPORT" ]; then
    log_ok "CheckM2 quality_report.tsv 已生成"
    echo "" | tee -a "$LOG_FILE"
    echo "高質量 MAGs（完整度 > 90%, 污染 < 5%）:" | tee -a "$LOG_FILE"
    awk -F'\t' 'NR>1 && $2>90 && $3<5 {
        printf "  %-40s 完整度:%.1f%%  污染:%.1f%%\n", $1, $2, $3
    }' "$CHECKM2_REPORT" | tee -a "$LOG_FILE" || echo "  無"
    echo "" | tee -a "$LOG_FILE"
    echo "中等質量 MAGs（完整度 > 50%, 污染 < 10%）:" | tee -a "$LOG_FILE"
    awk -F'\t' 'NR>1 && $2>50 && $3<10 {
        printf "  %-40s 完整度:%.1f%%  污染:%.1f%%\n", $1, $2, $3
    }' "$CHECKM2_REPORT" | head -10 | tee -a "$LOG_FILE"
else
    log_warn "找不到產生結果: $CHECKM2_REPORT"
fi

log_step "✅ CheckM2 品質評估完成！"
log "【生成的檔案】 $CHECKM2_DIR"
log "【完整 Log】 $LOG_FILE"
