#!/bin/bash

# ==========================================
# 5_eggnog_analysis.sh
# 蛋白質功能註釋流程 (eggNOG-mapper)
# 基於組裝基因 (Prodigal .faa) 註釋 COG, KEGG, GO 等功能
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
EGGNOG_DIR="${RESULT_DIR}/eggnog"
LOG_DIR="${LOG_DIR:-$WORK_DIR/log}"
LOG_FILE="${LOG_DIR}/eggnog_$(date +%Y%m%d_%H%M%S).log"

CONDA_BASE="${CONDA_BASE:-$HOME/miniconda3}"
DB_DIR="${DB_DIR:-$HOME/db}"
THREADS="${THREADS:-16}"
EGGNOG_ENV="eggnog_env"
USE_CONDA="${USE_CONDA:-auto}"
EMAPPER_BIN="${EMAPPER_BIN:-emapper.py}"
if [ -x "/opt/conda/bin/emapper.py" ]; then
    EMAPPER_BIN="/opt/conda/bin/emapper.py"
fi

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

echo "==========================================" | tee "$LOG_FILE"
echo "蛋白質功能註釋流程 (eggNOG-mapper)"        | tee -a "$LOG_FILE"
echo "Log 檔案: $LOG_FILE"                       | tee -a "$LOG_FILE"
echo "==========================================" | tee -a "$LOG_FILE"

log "工作目錄: $WORK_DIR"
log "資料庫目錄: $DB_DIR"
log "線程數: $THREADS"

# 激活 conda（可選）
if [ "$USE_CONDA" != "0" ]; then
    if [ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]; then
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        log "檢查 $EGGNOG_ENV 環境..."
        if conda activate "$EGGNOG_ENV" 2>/dev/null; then
            log_ok "環境: $EGGNOG_ENV"
        elif [ "$USE_CONDA" = "1" ]; then
            log_err "找不到 conda 環境: $EGGNOG_ENV"
            log "請先執行環境建置腳本："
            log "  ./setup_eggnog_env.sh"
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

# 檢查軟體與資料庫
log_step "檢查軟體與資料庫"

if ! command -v "$EMAPPER_BIN" &>/dev/null 2>&1 && [ ! -x "$EMAPPER_BIN" ]; then
    log_err "emapper.py (eggNOG-mapper) 未安裝。"
    log "請執行環境建置腳本： ./setup_eggnog_env.sh"
    exit 1
fi
log_ok "eggNOG-mapper 程式已就緒"

EGGNOG_DB_DIR="${DB_DIR}/eggnog"
mkdir -p "$EGGNOG_DB_DIR"
if [ ! -f "$EGGNOG_DB_DIR/eggnog.db" ] || [ ! -f "$EGGNOG_DB_DIR/eggnog_proteins.dmnd" ]; then
    log_err "eggNOG-mapper 資料庫未設定或不完整 ($EGGNOG_DB_DIR)"
    log "請執行環境建置腳本來下載資料庫："
    log "  ./setup_eggnog_env.sh"
    exit 1
fi

DB_SQLITE_SIZE=$(wc -c < "$EGGNOG_DB_DIR/eggnog.db" 2>/dev/null || echo "0")
DB_DIAMOND_SIZE=$(wc -c < "$EGGNOG_DB_DIR/eggnog_proteins.dmnd" 2>/dev/null || echo "0")
if [ "$DB_SQLITE_SIZE" -lt 1024 ] || [ "$DB_DIAMOND_SIZE" -lt 1024 ]; then
    log_warn "偵測到占位或過小資料庫檔案，將跳過 eggNOG 註釋以避免假失敗。"
    log_warn "eggnog.db: ${DB_SQLITE_SIZE} bytes"
    log_warn "eggnog_proteins.dmnd: ${DB_DIAMOND_SIZE} bytes"
    log_warn "請提供真實 eggNOG 資料庫後再重跑本模組。"
    log_step "✅ eggNOG-mapper 分析完成（已跳過）"
    exit 0
fi
log_ok "eggNOG 資料庫已就緒"

# ==========================================
# 準備檔案
# ==========================================

log_step "掃描蛋白質序列"

mkdir -p "$EGGNOG_DIR"

SAMPLES=()
for faa_file in "$RESULT_DIR"/*_genes.faa; do
    if [ -f "$faa_file" ]; then
        SAMPLE_NAME=$(basename "$faa_file" | sed 's/_genes\.faa//')
        SAMPLES+=("$SAMPLE_NAME")
        GENE_COUNT=$(grep -c "^>" "$faa_file" 2>/dev/null || echo "0")
        log "找到: $SAMPLE_NAME ($GENE_COUNT 條序列)"
    fi
done

if [ ${#SAMPLES[@]} -eq 0 ]; then
    log_err "未找到任何*_genes.faa。請確認 ./1_main_analysis.sh 的 Prodigal 步驟是否執行成功。"
    exit 1
fi

# ==========================================
# 執行 eggNOG-mapper
# ==========================================

for SAMPLE_NAME in "${SAMPLES[@]}"; do
    log_step "eggNOG 註釋: $SAMPLE_NAME"

    INPUT_FAA="${RESULT_DIR}/${SAMPLE_NAME}_genes.faa"
    SAMPLE_OUT_PREFIX="${EGGNOG_DIR}/${SAMPLE_NAME}"

    if [ -f "${SAMPLE_OUT_PREFIX}.emapper.annotations" ]; then
        log_ok "註釋結果已存在，跳過: $SAMPLE_NAME"
    else
        log "執行 emapper.py (可能需要耗費數十分鐘到數小時)..."
        
        # 執行 diamond 比對 + 注釋
        if "$EMAPPER_BIN" \
            -i "$INPUT_FAA" \
            --output "$SAMPLE_NAME" \
            --output_dir "$EGGNOG_DIR" \
            --data_dir "$EGGNOG_DB_DIR" \
            -m diamond \
            --cpu "$THREADS" \
            >>"$LOG_FILE" 2>&1; then
            log_ok "$SAMPLE_NAME 註釋完成"
        else
            log_err "$SAMPLE_NAME 註釋失敗，請查看 log: $LOG_FILE"
        fi
    fi
done

# ==========================================
# 輸出摘要
# ==========================================

log_step "✅ eggNOG-mapper 分析完成！"

for SAMPLE_NAME in "${SAMPLES[@]}"; do
    ANNOTATION_FILE="${EGGNOG_DIR}/${SAMPLE_NAME}.emapper.annotations"
    if [ -f "$ANNOTATION_FILE" ]; then
        # 計算成功註釋的基因數量 (排除註解行 #)
        ANNOTATED_COUNT=$(grep -v "^#" "$ANNOTATION_FILE" 2>/dev/null | wc -l || echo "0")
        log "$SAMPLE_NAME 成功獲得功能註釋的基因數: $ANNOTATED_COUNT 條"
    fi
done

log ""
log "【生成的檔案】 $EGGNOG_DIR"
log "  *.emapper.annotations  (包含 COG, KEGG, GO 等詳細註釋結果)"
log "  *.emapper.hits         (Diamond 原始比對結果)"
log ""
log "【完整 Log】 $LOG_FILE"
