#!/bin/bash

# ==========================================
# 3_lefse_analysis.sh
# 差異分析流程
# LEfSe + Venn圖 + 統計檢驗 + 火山圖
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
METAPHLAN_DIR="${RESULT_DIR}/metaphlan4"
DIFF_DIR="${RESULT_DIR}/differential"
LOG_DIR="${LOG_DIR:-$WORK_DIR/log}"
LOG_FILE="${LOG_DIR}/lefse_$(date +%Y%m%d_%H%M%S).log"

CONDA_BASE="${CONDA_BASE:-$HOME/miniconda3}"
DB_DIR="${DB_DIR:-$HOME/db}"
THREADS="${THREADS:-16}"
USE_CONDA="${USE_CONDA:-auto}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
if [ -x "/opt/conda/bin/python3" ]; then
    PYTHON_BIN="/opt/conda/bin/python3"
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
echo "差異分析流程 (LEfSe)"                      | tee -a "$LOG_FILE"
echo "Log 檔案: $LOG_FILE"                       | tee -a "$LOG_FILE"
echo "==========================================" | tee -a "$LOG_FILE"

log "工作目錄: $WORK_DIR"

# 激活環境（lefse 優先，否則用 easymetagenome）
log "激活分析環境..."
if [ "$USE_CONDA" != "0" ] && [ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]; then
    source "${CONDA_BASE}/etc/profile.d/conda.sh"
    if conda activate lefse 2>/dev/null; then
        log_ok "環境: lefse"
    elif conda activate easymetagenome 2>/dev/null; then
        log_ok "環境: easymetagenome"
    elif [ "$USE_CONDA" = "1" ]; then
        log_err "找不到可用環境（lefse 或 easymetagenome）"
        log "請創建環境:"
        log "  conda create -n lefse python=3.7 -y"
        log "  conda activate lefse"
        log "  conda install -c bioconda lefse -y"
        exit 1
    else
        log_warn "conda 環境不可用，改用當前 PATH 內工具"
    fi
elif [ "$USE_CONDA" = "1" ]; then
    log_err "找不到 conda: ${CONDA_BASE}/etc/profile.d/conda.sh"
    exit 1
else
    log "USE_CONDA=0 或 conda 缺失，使用當前 PATH 內工具"
fi

# 檢查必要檔案
log_step "檢查必要檔案"

if [ ! -f "$METAPHLAN_DIR/taxonomy.tsv" ]; then
    log_err "找不到 taxonomy.tsv: $METAPHLAN_DIR/taxonomy.tsv"
    log "請先執行: ./1_main_analysis.sh"
    exit 1
fi
log_ok "taxonomy.tsv"

if [ ! -f "$RESULT_DIR/metadata.txt" ]; then
    log_err "找不到 metadata.txt: $RESULT_DIR/metadata.txt"
    log "請先執行: ./1_main_analysis.sh"
    exit 1
fi
log_ok "metadata.txt"

mkdir -p "$DIFF_DIR"

# ==========================================
# 檢查分組
# ==========================================

log_step "檢查分組資訊"

log "metadata.txt 內容:"
cat "$RESULT_DIR/metadata.txt" | tee -a "$LOG_FILE"
log ""

GROUP_COUNT=$(tail -n +2 "$RESULT_DIR/metadata.txt" | cut -f2 | sort -u | wc -l)
log "分組數: $GROUP_COUNT"

SINGLE_GROUP=0
if [ "$GROUP_COUNT" -lt 2 ]; then
    log_warn "只有 1 個分組，無法進行差異分析"
    log_warn "請編輯 $RESULT_DIR/metadata.txt 設定分組"
    log ""
    log "範例格式："
    log "  #SampleID  Group"
    log "  SRR001     Control"
    log "  SRR002     Treatment"
    log ""
    log "跳過 LEfSe，僅執行 Venn 圖與統計分析..."
    SINGLE_GROUP=1
fi

# ==========================================
# LEfSe 差異分析
# ==========================================

log_step "LEfSe 差異分析"

cd "$DIFF_DIR"

if [ "$SINGLE_GROUP" -eq 1 ]; then
    log_warn "單一分組，跳過 LEfSe"
elif ! command -v lefse-format_input.py &>/dev/null; then
    log_warn "LEfSe 未安裝，跳過"
else
    log "步驟 1: 準備 LEfSe 輸入檔案..."

    # 用 Python 將 taxonomy.tsv + metadata.txt 整合成 LEfSe 格式
    "$PYTHON_BIN" - "$METAPHLAN_DIR/taxonomy.tsv" "$RESULT_DIR/metadata.txt" "$DIFF_DIR/lefse_input.txt" \
        >>"$LOG_FILE" 2>&1 << 'PYPREP'
import sys
import pandas as pd

taxa_path = sys.argv[1]
meta_path = sys.argv[2]
out_path  = sys.argv[3]

df = pd.read_csv(taxa_path, sep='\t', index_col=0, comment='#')
df.columns = [c.replace('_taxa', '') for c in df.columns]

meta = pd.read_csv(meta_path, sep='\t', comment='#', header=0, names=['SampleID', 'Group'])
meta = meta[meta['SampleID'].isin(df.columns)]

# 排列樣本順序與 metadata 一致
samples = meta['SampleID'].tolist()
df = df[samples]

with open(out_path, 'w') as f:
    # 第一行：class（分組）
    f.write('class\t' + '\t'.join(meta['Group'].tolist()) + '\n')
    # 資料行
    for idx, row in df.iterrows():
        f.write(f'{idx}\t' + '\t'.join(str(v) for v in row[samples].values) + '\n')

print(f"✓ lefse_input.txt 寫入完成 ({len(df)} 特徵, {len(samples)} 樣本)")
PYPREP

    if [ -f "$DIFF_DIR/lefse_input.txt" ]; then
        log_ok "lefse_input.txt"
    else
        log_err "LEfSe 輸入檔案生成失敗，跳過 LEfSe"
        goto_skip_lefse=1
    fi

    if [ "${goto_skip_lefse:-0}" -eq 0 ]; then
        log "步驟 2: 格式化..."
        if lefse-format_input.py \
            "$DIFF_DIR/lefse_input.txt" \
            "$DIFF_DIR/lefse_formatted.in" \
            -c 1 -u 2 -o 1000000 \
            >>"$LOG_FILE" 2>&1; then
            log_ok "lefse_formatted.in"
        else
            log_err "格式化失敗，跳過後續 LEfSe"
            goto_skip_lefse=1
        fi
    fi

    if [ "${goto_skip_lefse:-0}" -eq 0 ]; then
        log "步驟 3: 執行 LEfSe 分析..."
        if run_lefse.py \
            "$DIFF_DIR/lefse_formatted.in" \
            "$DIFF_DIR/lefse_results.res" \
            -l 2.0 -y 0 -a 0.05 --nlogs 3 \
            >>"$LOG_FILE" 2>&1; then
            log_ok "lefse_results.res"
        else
            log_err "LEfSe 分析失敗"
        fi

        log "步驟 4: 生成圖表..."
        if [ -f "$DIFF_DIR/lefse_results.res" ] && [ -s "$DIFF_DIR/lefse_results.res" ]; then
            lefse_plot_res.py "$DIFF_DIR/lefse_results.res" "$DIFF_DIR/lefse_barplot.pdf" \
                --format pdf --dpi 300 --width 10 --height 8 \
                >>"$LOG_FILE" 2>&1 && log_ok "lefse_barplot.pdf" || log_warn "條形圖生成失敗（可忽略）"

            lefse_plot_cladogram.py "$DIFF_DIR/lefse_results.res" "$DIFF_DIR/lefse_cladogram.pdf" \
                --format pdf --dpi 300 \
                >>"$LOG_FILE" 2>&1 && log_ok "lefse_cladogram.pdf" || log_warn "分支圖生成失敗（可忽略）"

            SIG_COUNT=$(awk '$3!="" && $3>2.0' "$DIFF_DIR/lefse_results.res" | wc -l)
            log "顯著差異特徵 (LDA > 2.0): $SIG_COUNT 個"
        else
            log_warn "lefse_results.res 為空，無顯著差異"
        fi
    fi
fi

# ==========================================
# Venn 圖（物種共有性）
# ==========================================

log_step "Venn 圖分析"
cd "$DIFF_DIR"

"$PYTHON_BIN" - "$METAPHLAN_DIR" "$RESULT_DIR" >>"$LOG_FILE" 2>&1 << 'PYVENN'
import sys, os
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

try:
    from matplotlib_venn import venn2, venn2_circles, venn3
except ImportError:
    print("⚠ matplotlib-venn 未安裝，跳過 Venn 圖")
    print("  安裝: pip install matplotlib-venn")
    sys.exit(0)

metaphlan_dir = sys.argv[1]
result_dir    = sys.argv[2]

df = pd.read_csv(f'{metaphlan_dir}/taxonomy.tsv', sep='\t', index_col=0, comment='#')
df.columns = [c.replace('_taxa', '') for c in df.columns]

species = df[df.index.str.contains('s__') & ~df.index.str.contains('t__')]
species = species[(species > 0).any(axis=1)]

meta = pd.read_csv(f'{result_dir}/metadata.txt', sep='\t', comment='#',
                   header=0, names=['SampleID', 'Group'])
samples = list(species.columns)

groups = {}
for _, row in meta.iterrows():
    g = row['Group']
    if g not in groups:
        groups[g] = []
    if row['SampleID'] in samples:
        groups[g].append(row['SampleID'])

print(f"樣本數: {len(samples)}, 分組: {list(groups.keys())}")

group_species = {}
for group, samp_list in groups.items():
    if len(samp_list) > 0:
        group_sp = set(species.index[species[samp_list].sum(axis=1) > 0])
        group_species[group] = group_sp
        print(f"  {group}: {len(group_sp)} 個物種")

group_list = list(group_species.keys())

if len(group_list) < 2:
    print("⚠ 分組數 < 2，跳過 Venn 圖")
    sys.exit(0)

fig, ax = plt.subplots(figsize=(8, 7))
if len(group_list) == 2:
    venn2([group_species[group_list[0]], group_species[group_list[1]]],
          set_labels=group_list, ax=ax)
    venn2_circles([group_species[group_list[0]], group_species[group_list[1]]],
                  linewidth=1.5, ax=ax)
elif len(group_list) >= 3:
    venn3([group_species[group_list[0]], group_species[group_list[1]], group_species[group_list[2]]],
          set_labels=group_list[:3], ax=ax)

ax.set_title('Species Venn Diagram', fontsize=14, fontweight='bold')
plt.tight_layout()
plt.savefig('venn_species.pdf', dpi=300, bbox_inches='tight')
plt.close()
print("✓ venn_species.pdf")

if len(group_list) == 2:
    common   = group_species[group_list[0]] & group_species[group_list[1]]
    unique_1 = group_species[group_list[0]] - group_species[group_list[1]]
    unique_2 = group_species[group_list[1]] - group_species[group_list[0]]
    with open('venn_summary.txt', 'w') as f:
        f.write(f"共有物種 ({len(common)}):\n")
        for sp in sorted(common): f.write(f"  {sp}\n")
        f.write(f"\n{group_list[0]} 特有 ({len(unique_1)}):\n")
        for sp in sorted(unique_1): f.write(f"  {sp}\n")
        f.write(f"\n{group_list[1]} 特有 ({len(unique_2)}):\n")
        for sp in sorted(unique_2): f.write(f"  {sp}\n")
    print("✓ venn_summary.txt")
PYVENN

"$PYTHON_BIN" - "$METAPHLAN_DIR" "$RESULT_DIR" >> "$LOG_FILE" 2>&1 << 'PYTEST'
import sys
import pandas as pd
import numpy as np
from scipy import stats
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

metaphlan_dir = sys.argv[1]
result_dir    = sys.argv[2]

df = pd.read_csv(f'{metaphlan_dir}/taxonomy.tsv', sep='\t', index_col=0, comment='#')
df.columns = [c.replace('_taxa', '') for c in df.columns]
species = df[df.index.str.contains('s__') & ~df.index.str.contains('t__')]
species = species[(species > 0).any(axis=1)]

meta = pd.read_csv(f'{result_dir}/metadata.txt', sep='\t', comment='#',
                   header=0, names=['SampleID', 'Group'])
groups = list(meta['Group'].unique())

if len(groups) < 2:
    print("⚠ 只有 1 個分組，跳過統計檢驗")
    sys.exit(0)

if len(groups) > 2:
    print(f"⚠ 統計檢驗目前僅支援 2 組比較（當前: {len(groups)} 組），取前 2 組")
    groups = groups[:2]

print(f"比較 {groups[0]} vs {groups[1]}")

group1_samples = [s for s in meta[meta['Group'] == groups[0]]['SampleID'].tolist() if s in species.columns]
group2_samples = [s for s in meta[meta['Group'] == groups[1]]['SampleID'].tolist() if s in species.columns]
print(f"  {groups[0]}: {len(group1_samples)} 個樣本")
print(f"  {groups[1]}: {len(group2_samples)} 個樣本")

if len(group1_samples) < 2 or len(group2_samples) < 2:
    print("⚠ 每組需至少 2 個樣本才能進行檢驗")
    sys.exit(0)

results = []
for taxon in species.index:
    vals1 = species.loc[taxon, group1_samples].values
    vals2 = species.loc[taxon, group2_samples].values
    try:
        stat, pval = stats.mannwhitneyu(vals1, vals2, alternative='two-sided')
        mean1 = vals1.mean()
        mean2 = vals2.mean()
        fold_change = (mean2 + 0.01) / (mean1 + 0.01)
        results.append({
            'Taxon': taxon,
            f'{groups[0]}_mean': round(mean1, 4),
            f'{groups[1]}_mean': round(mean2, 4),
            'Fold_Change': round(fold_change, 4),
            'Log2FC': round(np.log2(fold_change), 4),
            'P_value': pval,
            'Significant': 'Yes' if pval < 0.05 else 'No'
        })
    except Exception:
        pass

results_df = pd.DataFrame(results).sort_values('P_value')
results_df.to_csv('statistical_test.txt', sep='\t', index=False)
sig_n = (results_df['P_value'] < 0.05).sum()
print(f"✓ statistical_test.txt  (顯著物種: {sig_n})")

# 火山圖
results_df['neg_log10p'] = -np.log10(results_df['P_value'] + 1e-300)
fig, ax = plt.subplots(figsize=(10, 8))
nonsig = results_df[results_df['P_value'] >= 0.05]
sig    = results_df[results_df['P_value'] <  0.05]
ax.scatter(nonsig['Log2FC'], nonsig['neg_log10p'], c='gray', alpha=0.5, s=20, label='Non-significant')
ax.scatter(sig['Log2FC'],    sig['neg_log10p'],    c='red',  alpha=0.7, s=30, label='Significant (p<0.05)')
ax.axhline(-np.log10(0.05), color='blue', linestyle='--', linewidth=1, alpha=0.5)
ax.axvline(0,               color='black', linestyle='-',  linewidth=0.5, alpha=0.3)
ax.set_xlabel('log2(Fold Change)', fontsize=12)
ax.set_ylabel('-log10(P value)',   fontsize=12)
ax.set_title('Volcano Plot', fontsize=14, fontweight='bold')
ax.legend()
ax.grid(alpha=0.3)
plt.tight_layout()
plt.savefig('volcano_plot.pdf', dpi=300, bbox_inches='tight')
plt.close()
print("✓ volcano_plot.pdf")
PYTEST

if [ $? -eq 0 ]; then
    log_ok "統計檢驗完成"
else
    log_warn "統計檢驗部分失敗（可能分組不足），查看 log"
fi

# ==========================================
# 摘要
# ==========================================

cd "$WORK_DIR"
log_step "✅ 差異分析完成！"

log "【生成的檔案】result/differential/"
# 安全列出檔案，不用 ls glob 觸發錯誤
for f in "$DIFF_DIR"/*.res "$DIFF_DIR"/*.pdf "$DIFF_DIR"/*.txt; do
    [ -f "$f" ] && log "  $(basename "$f")"
done

log ""
if [ -f "$DIFF_DIR/lefse_results.res" ]; then
    SIG_LEF=$(awk '$3!="" && $3>2.0' "$DIFF_DIR/lefse_results.res" 2>/dev/null | wc -l)
    log "LEfSe 顯著特徵: $SIG_LEF"
fi
if [ -f "$DIFF_DIR/statistical_test.txt" ]; then
    SIG_STAT=$(tail -n +2 "$DIFF_DIR/statistical_test.txt" | awk -F'\t' '$NF=="Yes"' | wc -l)
    log "統計顯著物種: $SIG_STAT (p<0.05)"
fi
log ""
log "【完整 Log】$LOG_FILE"
log ""
log "【下一步】"
log "  可視化: ./4_visualization.sh"
