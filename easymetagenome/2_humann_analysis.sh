#!/bin/bash

# ==========================================
# 2_humann_analysis.sh
# 功能分析流程 (humann4 環境)
# HUMAnN4: 代謝通路、基因家族、功能註釋
# 修復版：安全錯誤處理 + 詳細 Log
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
HUMANN_DIR="${RESULT_DIR}/humann4"
LOG_DIR="${LOG_DIR:-$WORK_DIR/log}"
LOG_FILE="${LOG_DIR}/humann_$(date +%Y%m%d_%H%M%S).log"

CONDA_BASE="${CONDA_BASE:-$HOME/miniconda3}"
if [ ! -f "${CONDA_BASE}/etc/profile.d/conda.sh" ] && [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
    CONDA_BASE="/opt/conda"
fi
DB_DIR="${DB_DIR:-$HOME/db}"
THREADS="${THREADS:-16}"
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

echo "==========================================" | tee "$LOG_FILE"
echo "功能分析流程 (HUMAnN4)"                    | tee -a "$LOG_FILE"
echo "Log 檔案: $LOG_FILE"                       | tee -a "$LOG_FILE"
echo "==========================================" | tee -a "$LOG_FILE"

log "工作目錄: $WORK_DIR"
log "資料庫目錄: $DB_DIR"
log "線程數:   $THREADS"

# 激活 conda（可選）
if [ "$USE_CONDA" != "0" ]; then
    if [ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]; then
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        log "激活 humann4 環境..."
        if conda activate humann4 2>/dev/null; then
            log_ok "環境: humann4"
        elif [ "$USE_CONDA" = "1" ]; then
            log_err "humann4 環境不存在"
            log "請創建環境:"
            log "  conda create -n humann4 python=3.10 -y"
            log "  conda activate humann4"
            log "  conda install -c bioconda humann metaphlan -y"
            log "然後下載資料庫:"
            log "  humann_databases --download chocophlan full $DB_DIR/humann4"
            log "  humann_databases --download uniref uniref90_diamond $DB_DIR/humann4"
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

# 檢查 HUMAnN 資料庫
log_step "檢查資料庫"
if ! command -v humann &>/dev/null; then
    log_err "humann 未安裝或不在 PATH 中。"
    log "請先安裝 HUMAnN（或啟用 humann4 環境）後再重試。"
    exit 1
fi
log_ok "HUMAnN 程式已就緒"

for db_name in chocophlan uniref; do
    db_path="$DB_DIR/humann4/$db_name"
    if [ ! -d "$db_path" ] || [ -z "$(ls -A "$db_path" 2>/dev/null)" ]; then
        log_err "HUMAnN 資料庫缺失或為空: $db_path"
        log "請下載資料庫（可能需要數十 GB 空間）："
        log "  conda activate humann4"
        log "  humann_databases --download chocophlan full $DB_DIR/humann4"
        log "  humann_databases --download uniref uniref90_diamond $DB_DIR/humann4"
        exit 1
    fi
done
log_ok "HUMAnN 資料庫已就緒"

# 創建輸出目錄
mkdir -p "$HUMANN_DIR"

# ==========================================
# 掃描樣本
# ==========================================

log_step "掃描樣本"
SAMPLES=()
for taxa_file in "$RESULT_DIR"/*_taxa.tsv; do
    if [ -f "$taxa_file" ]; then
        SAMPLE_NAME=$(basename "$taxa_file" | sed 's/_taxa\.tsv//')
        SAMPLES+=("$SAMPLE_NAME")
        log_ok "$SAMPLE_NAME"
    fi
done

if [ ${#SAMPLES[@]} -eq 0 ]; then
    log_err "未找到樣本（需要 result/*_taxa.tsv），請先執行: ./1_main_analysis.sh"
    exit 1
fi
log "找到 ${#SAMPLES[@]} 個樣本"

# ==========================================
# HUMAnN4 分析
# ==========================================

for SAMPLE_NAME in "${SAMPLES[@]}"; do

    log_step "HUMAnN4 分析: $SAMPLE_NAME"

    QC_R1="${TEMP_DIR}/qc/${SAMPLE_NAME}_1.fastq"
    QC_R2="${TEMP_DIR}/qc/${SAMPLE_NAME}_2.fastq"

    if [ ! -f "$QC_R1" ] || [ ! -f "$QC_R2" ]; then
        log_err "找不到質控序列（$QC_R1），跳過"
        continue
    fi

    # 合併配對讀長（HUMAnN 需要單個檔案）
    MERGED_FASTQ="${TEMP_DIR}/qc/${SAMPLE_NAME}_merged.fastq"
    if [ ! -f "$MERGED_FASTQ" ] || [ ! -s "$MERGED_FASTQ" ]; then
        log "合併配對讀長..."
        if cat "$QC_R1" "$QC_R2" > "$MERGED_FASTQ"; then
            log_ok "合併完成"
        else
            log_err "合併失敗，跳過"
            continue
        fi
    else
        log_ok "合併檔案已存在，跳過"
    fi

    # 執行 HUMAnN4
    SAMPLE_HUMANN_DIR="${HUMANN_DIR}/${SAMPLE_NAME}"
    GENE_OUT="${SAMPLE_HUMANN_DIR}/${SAMPLE_NAME}_genefamilies.tsv"
    MERGED_GENE_OUT="${SAMPLE_HUMANN_DIR}/${SAMPLE_NAME}_merged_genefamilies.tsv"

    if [ -f "$GENE_OUT" ] && [ -s "$GENE_OUT" ]; then
        log_ok "HUMAnN4 結果已存在，跳過"
    else
        log "執行 HUMAnN4（預計 30-120 分鐘）..."
        mkdir -p "$SAMPLE_HUMANN_DIR"

        # 讓 HUMAnN4 直接利用我們之前跑好的 MetaPhlAn4 的分類結果，避免自己去呼叫產生版本錯誤
        TAXA_PROFILE="${RESULT_DIR}/${SAMPLE_NAME}_taxa.tsv"

        if [ ! -f "$TAXA_PROFILE" ]; then
            log_err "找不到預先跑好的物種分類檔: $TAXA_PROFILE"
            continue
        fi

        if humann \
            --input "$MERGED_FASTQ" \
            --output "$SAMPLE_HUMANN_DIR" \
            --threads "$THREADS" \
            --nucleotide-database "$DB_DIR/humann4/chocophlan" \
            --protein-database "$DB_DIR/humann4/uniref" \
            --taxonomic-profile "$TAXA_PROFILE" \
            --bypass-nucleotide-index \
            --remove-temp-output \
            >>"$LOG_FILE" 2>&1; then
            log_ok "HUMAnN4 完成"
        else
            log_err "HUMAnN4 失敗，查看 log: $LOG_FILE"
            continue
        fi
    fi

    # 重命名輸出檔案（HUMAnN 用輸入檔名命名）
    for suffix in genefamilies pathabundance pathcoverage; do
        merged_file="${SAMPLE_HUMANN_DIR}/${SAMPLE_NAME}_merged_${suffix}.tsv"
        target_file="${SAMPLE_HUMANN_DIR}/${SAMPLE_NAME}_${suffix}.tsv"
        if [ -f "$merged_file" ] && [ ! -f "$target_file" ]; then
            mv "$merged_file" "$target_file"
            log_ok "重命名: ${SAMPLE_NAME}_${suffix}.tsv"
        fi
    done

done

# ==========================================
# 合併結果
# ==========================================

log_step "合併 HUMAnN4 結果"

for suffix in genefamilies pathabundance pathcoverage; do
    # 安全檢查：先確認有沒有檔案再執行
    FILE_COUNT=$(ls "$HUMANN_DIR"/*/*_${suffix}.tsv 2>/dev/null | wc -l)
    if [ "$FILE_COUNT" -gt 0 ]; then
        log "合併 ${suffix}..."
        if humann_join_tables \
            --input "$HUMANN_DIR" \
            --output "$HUMANN_DIR/${suffix}_merged.tsv" \
            --file_name "$suffix" \
            >>"$LOG_FILE" 2>&1; then
            log_ok "${suffix}_merged.tsv"
        else
            log_err "合併 ${suffix} 失敗"
        fi
    else
        log_warn "無 ${suffix} 檔案可合併"
    fi
done

# ==========================================
# 標準化與分層
# ==========================================

log_step "標準化結果"

if [ -f "$HUMANN_DIR/genefamilies_merged.tsv" ]; then
    log "標準化基因家族（CPM）..."
    if humann_renorm_table \
        --input "$HUMANN_DIR/genefamilies_merged.tsv" \
        --output "$HUMANN_DIR/genefamilies_cpm.tsv" \
        --units cpm >>"$LOG_FILE" 2>&1; then
        log_ok "genefamilies_cpm.tsv"
    else
        log_err "基因家族標準化失敗"
    fi
fi

if [ -f "$HUMANN_DIR/pathabundance_merged.tsv" ]; then
    log "標準化通路豐度（relab）..."
    if humann_renorm_table \
        --input "$HUMANN_DIR/pathabundance_merged.tsv" \
        --output "$HUMANN_DIR/pathabundance_relab.tsv" \
        --units relab >>"$LOG_FILE" 2>&1; then
        log_ok "pathabundance_relab.tsv"
    else
        log_err "通路豐度標準化失敗"
    fi
fi

if [ -f "$HUMANN_DIR/genefamilies_cpm.tsv" ]; then
    log "分層基因家族..."
    if humann_split_stratified_table \
        --input "$HUMANN_DIR/genefamilies_cpm.tsv" \
        --output "$HUMANN_DIR" >>"$LOG_FILE" 2>&1; then
        log_ok "genefamilies_cpm_stratified/unstratified.tsv"
    else
        log_err "分層失敗"
    fi
fi

# ==========================================
# 功能註釋
# ==========================================

log_step "功能註釋"

UNSTRAT="$HUMANN_DIR/genefamilies_cpm_unstratified.tsv"
if [ -f "$UNSTRAT" ]; then
    for group_name in uniref90_go uniref90_ko uniref90_level4ec; do
        out_name="${group_name##uniref90_}_abundance.tsv"
        log "分組到 ${group_name}..."
        humann_regroup_table \
            --input "$UNSTRAT" \
            --output "$HUMANN_DIR/${out_name}" \
            --groups "$group_name" \
            >>"$LOG_FILE" 2>&1 && log_ok "$out_name" || log_warn "${group_name} 資料庫缺失，跳過"
    done
else
    log_warn "找不到 unstratified 檔案，跳過功能註釋"
fi

# ==========================================
# 可視化
# ==========================================

log_step "通路條形圖"

if [ -f "$HUMANN_DIR/pathabundance_relab.tsv" ]; then
    log "繪製通路條形圖..."
    humann_barplot \
        --input "$HUMANN_DIR/pathabundance_relab.tsv" \
        --output "$HUMANN_DIR/pathway_barplot.png" \
        --focal-feature UNINTEGRATED \
        --focal-metadata UNINTEGRATED \
        --last-metadata UNINTEGRATED \
        --scaling logstack \
        --top 25 \
        --remove-zeros \
        >>"$LOG_FILE" 2>&1 && log_ok "pathway_barplot.png" || log_warn "繪圖失敗（可忽略）"
fi

# ==========================================
# 最終摘要
# ==========================================

log_step "✅ HUMAnN4 功能分析完成！"

log "已處理 ${#SAMPLES[@]} 個樣本"
log ""
log "【生成的結果】result/humann4/"
log "  genefamilies_merged.tsv    (基因家族豐度)"
log "  pathabundance_merged.tsv   (通路豐度)"
log "  genefamilies_cpm.tsv       (CPM標準化)"
log "  pathabundance_relab.tsv    (相對豐度)"
log "  go_abundance.tsv           (GO分組)"
log "  kegg_ko_abundance.tsv      (KEGG KO)"
log "  ec_level4ec_abundance.tsv  (EC編號)"
log ""
log "【完整 Log】$LOG_FILE"
log ""
log "【下一步】"
log "  1. 差異分析: ./3_lefse_analysis.sh"
log "  2. 可視化:   ./4_visualization.sh"
