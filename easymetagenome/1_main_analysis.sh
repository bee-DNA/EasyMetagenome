#!/bin/bash

# ==========================================
# 1_main_analysis.sh
# 主要分析流程 (easymetagenome 環境)
# 質控 + 組裝 + 基因預測 + 物種分類 + Binning
# 修復版：安全錯誤處理 + 詳細 Log
# ==========================================

# 不使用 set -e，改為手動檢查每個關鍵步驟
set -u  # 未定義變數報錯（保留）

# ==========================================
# 配置
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-$SCRIPT_DIR}"
SEQ_DIR="${SEQ_DIR:-$WORK_DIR}"
RESULT_DIR="${RESULT_DIR:-$WORK_DIR/result}"
TEMP_DIR="${TEMP_DIR:-$WORK_DIR/temp}"
LOG_DIR="${LOG_DIR:-$WORK_DIR/log}"
BIN_DIR="${RESULT_DIR}/bins"
LOG_FILE="${LOG_DIR}/pipeline_$(date +%Y%m%d_%H%M%S).log"

CONDA_BASE="${CONDA_BASE:-$HOME/miniconda3}"
DB_DIR="${DB_DIR:-$HOME/db}"
THREADS="${THREADS:-16}"
USE_CONDA="${USE_CONDA:-auto}"

# ==========================================
# Log 函數
# ==========================================

log() {
    echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_step() {
    echo "" | tee -a "$LOG_FILE"
    echo "==========================================" | tee -a "$LOG_FILE"
    echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"
    echo "==========================================" | tee -a "$LOG_FILE"
}

log_ok()   { echo "[$(date '+%H:%M:%S')] ✓ $*" | tee -a "$LOG_FILE"; }
log_warn() { echo "[$(date '+%H:%M:%S')] ⚠ $*" | tee -a "$LOG_FILE"; }
log_err()  { echo "[$(date '+%H:%M:%S')] ❌ $*" | tee -a "$LOG_FILE"; }

# ==========================================
# 開始
# ==========================================

mkdir -p "$LOG_DIR"

echo "==========================================" | tee "$LOG_FILE"
echo "主要分析流程 (easymetagenome)" | tee -a "$LOG_FILE"
echo "Log 檔案: $LOG_FILE" | tee -a "$LOG_FILE"
echo "==========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

log "工作目錄: $WORK_DIR"
log "序列目錄: $SEQ_DIR"
log "資料庫目錄: $DB_DIR"
log "線程數: $THREADS"

# 激活 conda（可選）
if [ "$USE_CONDA" != "0" ]; then
    if [ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]; then
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        log "激活 easymetagenome 環境..."
        if conda activate easymetagenome 2>/dev/null; then
            log_ok "環境: easymetagenome"
        elif [ "$USE_CONDA" = "1" ]; then
            log_err "easymetagenome 環境不存在，請先執行: ./setup_easymetagenome_env.sh"
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

# 創建目錄結構
mkdir -p "$RESULT_DIR" "$TEMP_DIR" "$BIN_DIR"
mkdir -p "$TEMP_DIR/qc" "$TEMP_DIR/megahit" "$TEMP_DIR/prodigal" "$TEMP_DIR/mapping"
mkdir -p "$RESULT_DIR/metaphlan4" "$RESULT_DIR/checkm"

# ==========================================
# 掃描樣本
# ==========================================

log_step "步驟 0：掃描樣本"
SAMPLES=()
for r1_file in "$SEQ_DIR"/*_1.f*; do
    if [ -f "$r1_file" ]; then
        SAMPLE_NAME=$(basename "$r1_file" | sed 's/_1\.f.*//')
        SAMPLES+=("$SAMPLE_NAME")
        log_ok "$SAMPLE_NAME"
    fi
done

if [ ${#SAMPLES[@]} -eq 0 ]; then
    log_err "未找到 FASTQ 檔案（格式：*_1.fastq 或 *_1.fq.gz）"
    exit 1
fi
log "找到 ${#SAMPLES[@]} 個樣本"

# ==========================================
# 主要分析迴圈
# ==========================================

for SAMPLE_NAME in "${SAMPLES[@]}"; do

    log_step "處理樣本: $SAMPLE_NAME"

    # 查找讀長檔案
    READ_1=$(find "$SEQ_DIR" -maxdepth 1 -name "${SAMPLE_NAME}_1.f*" 2>/dev/null | head -1)
    READ_2=$(find "$SEQ_DIR" -maxdepth 1 -name "${SAMPLE_NAME}_2.f*" 2>/dev/null | head -1)

    if [ -z "$READ_1" ] || [ -z "$READ_2" ]; then
        log_err "找不到配對讀長，跳過 $SAMPLE_NAME"
        continue
    fi

    log "R1: $READ_1"
    log "R2: $READ_2"

    # ========== 步驟 1: 質控 ==========
    log_step "步驟 1：質量控制 (FastP) - $SAMPLE_NAME"

    FASTP_OUT_1="${TEMP_DIR}/qc/${SAMPLE_NAME}_1.fastq"
    FASTP_OUT_2="${TEMP_DIR}/qc/${SAMPLE_NAME}_2.fastq"

    if [ -f "$FASTP_OUT_1" ] && [ -s "$FASTP_OUT_1" ]; then
        log_ok "跳過（已存在）"
    else
        if ! command -v fastp &>/dev/null; then
            log_err "fastp 未安裝，跳過質控（直接使用原始讀長）"
            FASTP_OUT_1="$READ_1"
            FASTP_OUT_2="$READ_2"
        else
            log "執行 fastp..."
            if fastp -i "$READ_1" -I "$READ_2" \
                  -o "$FASTP_OUT_1" -O "$FASTP_OUT_2" \
                  -h "$TEMP_DIR/qc/${SAMPLE_NAME}.html" \
                  -j "$TEMP_DIR/qc/${SAMPLE_NAME}.json" \
                  -w "$THREADS" --detect_adapter_for_pe --length_required 50 \
                  2>>"$LOG_FILE"; then
                log_ok "FastP 完成"
            else
                log_err "FastP 失敗，改用原始讀長"
                FASTP_OUT_1="$READ_1"
                FASTP_OUT_2="$READ_2"
            fi
        fi
    fi

    # ========== 步驟 2: 組裝 ==========
    log_step "步驟 2：序列組裝 (MEGAHIT) - $SAMPLE_NAME"

    ASSEMBLY_DIR="${TEMP_DIR}/megahit/${SAMPLE_NAME}"
    ASSEMBLY_CONTIGS="${ASSEMBLY_DIR}/final.contigs.fa"

    # 安全檢查 MEGAHIT 是否完成（不用 grep 直接觸發 set -e）
    MEGAHIT_DONE=0
    if [ -f "$ASSEMBLY_CONTIGS" ] && [ -f "${ASSEMBLY_DIR}/log" ]; then
        if grep -q "ALL DONE" "${ASSEMBLY_DIR}/log" 2>/dev/null; then
            MEGAHIT_DONE=1
        fi
    fi

    if [ "$MEGAHIT_DONE" -eq 1 ]; then
        CONTIG_COUNT=$(grep -c "^>" "$ASSEMBLY_CONTIGS" 2>/dev/null || echo "0")
        log_ok "跳過（已存在，Contigs: $CONTIG_COUNT）"
    else
        if ! command -v megahit &>/dev/null; then
            log_err "megahit 未安裝，跳過組裝"
            continue
        fi
        rm -rf "$ASSEMBLY_DIR" 2>/dev/null || true
        log "執行 megahit..."
        if megahit -1 "$FASTP_OUT_1" -2 "$FASTP_OUT_2" \
                -o "$ASSEMBLY_DIR" -t "$THREADS" -m 0.4 \
                --k-min 21 --k-max 141 --k-step 12 \
                2>>"$LOG_FILE"; then
            CONTIG_COUNT=$(grep -c "^>" "$ASSEMBLY_CONTIGS" 2>/dev/null || echo "0")
            log_ok "組裝完成 (Contigs: $CONTIG_COUNT)"
        else
            log_err "MEGAHIT 失敗（記憶體不足？），跳過此樣本"
            continue
        fi
    fi

    # 確認 contigs 存在才繼續
    if [ ! -f "$ASSEMBLY_CONTIGS" ]; then
        log_err "找不到 contigs 檔案，跳過此樣本"
        continue
    fi

    # ========== 步驟 3: 基因預測 ==========
    log_step "步驟 3：基因預測 (Prodigal) - $SAMPLE_NAME"

    GENE_GFF="${RESULT_DIR}/${SAMPLE_NAME}_genes.gff"
    GENE_PROTEIN="${RESULT_DIR}/${SAMPLE_NAME}_genes.faa"
    GENE_NUCL="${RESULT_DIR}/${SAMPLE_NAME}_genes.fna"

    if [ -f "$GENE_PROTEIN" ] && [ -s "$GENE_PROTEIN" ]; then
        GENE_COUNT=$(grep -c "^>" "$GENE_PROTEIN" 2>/dev/null || echo "0")
        log_ok "跳過（已存在，基因數: $GENE_COUNT）"
    else
        if ! command -v prodigal &>/dev/null; then
            log_warn "Prodigal 未安裝，跳過基因預測"
        else
            log "執行 prodigal..."
            if prodigal -i "$ASSEMBLY_CONTIGS" \
                     -o "$GENE_GFF" -a "$GENE_PROTEIN" -d "$GENE_NUCL" \
                     -f gff -p meta \
                     >"$TEMP_DIR/prodigal/${SAMPLE_NAME}.log" 2>&1; then
                GENE_COUNT=$(grep -c "^>" "$GENE_PROTEIN" 2>/dev/null || echo "0")
                log_ok "基因預測完成 (基因數: $GENE_COUNT)"
            else
                log_err "Prodigal 失敗，查看: $TEMP_DIR/prodigal/${SAMPLE_NAME}.log"
            fi
        fi
    fi

    # ========== 步驟 4: MetaPhlAn4 ==========
    log_step "步驟 4：物種分類 (MetaPhlAn4) - $SAMPLE_NAME"

    METAPHLAN_OUT="${RESULT_DIR}/${SAMPLE_NAME}_taxa.tsv"

    if [ -f "$METAPHLAN_OUT" ] && [ -s "$METAPHLAN_OUT" ]; then
        log_ok "跳過（已存在）"
    else
        if ! command -v metaphlan &>/dev/null; then
            log_warn "metaphlan 未安裝，跳過"
        elif [ ! -d "$DB_DIR/metaphlan4" ]; then
            log_warn "MetaPhlAn4 資料庫不存在: $DB_DIR/metaphlan4"
            log_warn "請執行: metaphlan --install --db_dir $DB_DIR/metaphlan4"
        else
            log "執行 metaphlan（stdin 合流模式，支援各版本）..."
            # 用 cat 合流 R1+R2 透過 stdin 輸入，繞過新版 -1/-2 需 --subsampling_paired 的限制
            if cat "$FASTP_OUT_1" "$FASTP_OUT_2" | \
                metaphlan \
                      --input_type fastq --nproc "$THREADS" \
                      --db_dir "$DB_DIR/metaphlan4" \
                      --index mpa_vOct22_CHOCOPhlAnSGB_202403 \
                      -o "$METAPHLAN_OUT" \
                      2>>"$LOG_FILE"; then
                log_ok "MetaPhlAn4 完成"
            else
                log_err "MetaPhlAn4 失敗，查看 log: $LOG_FILE"
            fi
        fi
    fi

    # ========== 步驟 5: 序列比對 ==========
    log_step "步驟 5：序列比對 (Bowtie2) - $SAMPLE_NAME"

    BAM_FILE="${TEMP_DIR}/mapping/${SAMPLE_NAME}.sorted.bam"
    SAM_FILE="${TEMP_DIR}/mapping/${SAMPLE_NAME}.sam"

    if [ -f "$BAM_FILE" ] && [ -s "$BAM_FILE" ]; then
        log_ok "跳過（已存在）"
    else
        if ! command -v bowtie2 &>/dev/null || ! command -v samtools &>/dev/null; then
            log_warn "bowtie2/samtools 未安裝，跳過比對（無法執行 Binning）"
        else
            # 建立索引（只在需要時）
            if [ ! -f "${ASSEMBLY_CONTIGS}.1.bt2" ]; then
                log "建立 Bowtie2 索引..."
                if ! bowtie2-build "$ASSEMBLY_CONTIGS" "$ASSEMBLY_CONTIGS" \
                        --threads "$THREADS" >>"$LOG_FILE" 2>&1; then
                    log_err "bowtie2-build 失敗，跳過比對"
                    continue
                fi
            fi

            # 比對
            log "執行比對..."
            if bowtie2 -x "$ASSEMBLY_CONTIGS" \
                    -1 "$FASTP_OUT_1" -2 "$FASTP_OUT_2" \
                    --threads "$THREADS" \
                    -S "$SAM_FILE" \
                    2>>"$LOG_FILE"; then

                log "轉換 BAM 並排序..."
                if samtools view -bS "$SAM_FILE" 2>>"$LOG_FILE" | \
                   samtools sort -@ "$THREADS" -o "$BAM_FILE" 2>>"$LOG_FILE"; then
                    samtools index "$BAM_FILE" 2>>"$LOG_FILE"
                    rm -f "$SAM_FILE"
                    log_ok "比對完成"
                else
                    log_err "samtools 轉換失敗"
                fi
            else
                log_err "bowtie2 比對失敗"
            fi
        fi
    fi

    # ========== 步驟 6: Binning ==========
    log_step "步驟 6：基因組 Binning (MetaBAT2) - $SAMPLE_NAME"

    SAMPLE_BIN_DIR="${BIN_DIR}/${SAMPLE_NAME}"

    # 安全檢查（不直接用 ls 做條件）
    BIN_EXISTS=0
    if [ -d "$SAMPLE_BIN_DIR" ]; then
        BIN_COUNT_EXIST=$(ls "$SAMPLE_BIN_DIR"/*.fa 2>/dev/null | wc -l)
        if [ "$BIN_COUNT_EXIST" -gt 0 ]; then
            BIN_EXISTS=1
        fi
    fi

    if [ "$BIN_EXISTS" -eq 1 ]; then
        log_ok "跳過（已存在 ${BIN_COUNT_EXIST} bins）"
    else
        if ! command -v metabat2 &>/dev/null; then
            log_warn "MetaBAT2 未安裝，跳過 Binning"
        elif [ ! -f "$BAM_FILE" ]; then
            log_warn "缺少 BAM 檔案，跳過 Binning"
        else
            mkdir -p "$SAMPLE_BIN_DIR"

            log "計算深度..."
            if ! jgi_summarize_bam_contig_depths \
                    --outputDepth "${TEMP_DIR}/mapping/${SAMPLE_NAME}_depth.txt" \
                    "$BAM_FILE" >>"$LOG_FILE" 2>&1; then
                log_err "jgi_summarize_bam_contig_depths 失敗"
            else
                log "執行 MetaBAT2..."
                if metabat2 -i "$ASSEMBLY_CONTIGS" \
                         -a "${TEMP_DIR}/mapping/${SAMPLE_NAME}_depth.txt" \
                         -o "${SAMPLE_BIN_DIR}/bin" \
                         -m 1500 --minCV 1.0 --maxEdges 200 \
                         -t "$THREADS" \
                         >>"$LOG_FILE" 2>&1; then
                    BIN_COUNT=$(ls "$SAMPLE_BIN_DIR"/*.fa 2>/dev/null | wc -l || echo "0")
                    log_ok "Binning 完成 (Bins: $BIN_COUNT)"
                else
                    log_err "MetaBAT2 失敗"
                fi
            fi
        fi
    fi

done  # 樣本迴圈結束

# ==========================================
# 後處理：合併結果
# ==========================================

log_step "後處理：合併分析結果"

# 合併 MetaPhlAn4 結果
TAXA_FILES=("$RESULT_DIR"/*_taxa.tsv)
if [ -f "${TAXA_FILES[0]}" ]; then
    log "合併 MetaPhlAn4 結果..."
    if command -v merge_metaphlan_tables.py &>/dev/null; then
        if merge_metaphlan_tables.py "$RESULT_DIR"/*_taxa.tsv \
                >"$RESULT_DIR/metaphlan4/taxonomy.tsv" 2>>"$LOG_FILE"; then
            cd "$RESULT_DIR/metaphlan4"
            sed '/^#/d' taxonomy.tsv > taxonomy_clean.tsv 2>/dev/null || true
            grep -E "(s__|unclassified)" taxonomy_clean.tsv > taxonomy.spf 2>/dev/null || touch taxonomy.spf
            cd "$WORK_DIR"
            log_ok "taxonomy.tsv"
        else
            log_err "merge_metaphlan_tables.py 執行失敗"
        fi
    else
        log_warn "merge_metaphlan_tables.py 未找到，跳過合併"
    fi
fi

# 生成 metadata.txt
if [ ! -f "$RESULT_DIR/metadata.txt" ]; then
    log "生成 metadata.txt..."
    echo -e "#SampleID\tGroup" > "$RESULT_DIR/metadata.txt"
    count=0
    for SAMPLE in "${SAMPLES[@]}"; do
        if [ $((count % 2)) -eq 0 ]; then
            echo -e "${SAMPLE}\tGroup1" >> "$RESULT_DIR/metadata.txt"
        else
            echo -e "${SAMPLE}\tGroup2" >> "$RESULT_DIR/metadata.txt"
        fi
        count=$((count + 1))
    done
    log_ok "metadata.txt（樣本依序自動分配為 Group1 和 Group2，請依需求編輯）"
fi

# 基因組質量評估已移至 1.5_checkm2_analysis.sh


# ==========================================
# 最終摘要
# ==========================================

log_step "✅ 主要分析完成！"

echo "" | tee -a "$LOG_FILE"
echo "已處理 ${#SAMPLES[@]} 個樣本" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "【生成的結果】" | tee -a "$LOG_FILE"
echo "  物種分類: result/metaphlan4/taxonomy.tsv" | tee -a "$LOG_FILE"
GENE_FILES=$(ls "$RESULT_DIR"/*_genes.faa 2>/dev/null | wc -l || echo "0")
echo "  基因預測: ${GENE_FILES} 個蛋白序列檔案" | tee -a "$LOG_FILE"

TOTAL_BINS=0
for sample_dir in "$BIN_DIR"/*/; do
    if [ -d "$sample_dir" ] && [ "$(basename "$sample_dir")" != "all_bins" ]; then
        COUNT=$(ls "$sample_dir"/*.fa 2>/dev/null | wc -l || echo "0")
        TOTAL_BINS=$((TOTAL_BINS + COUNT))
    fi
done
echo "  基因組 Bins: ${TOTAL_BINS} 個" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "【完整 Log】$LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "【下一步】" | tee -a "$LOG_FILE"
echo "  1. 基因質檢 (CheckM2): ./1.5_checkm2_analysis.sh" | tee -a "$LOG_FILE"
echo "  2. 功能分析 (HUMAnN4): ./2_humann_analysis.sh" | tee -a "$LOG_FILE"
echo "  3. 差異分析 (LEfSe):   ./3_lefse_analysis.sh" | tee -a "$LOG_FILE"
echo "  4. 可視化:             ./4_visualization.sh" | tee -a "$LOG_FILE"
echo "  5. 蛋白質註釋(eggNOG): ./5_eggnog_analysis.sh" | tee -a "$LOG_FILE"
