#!/bin/bash

# ==========================================
# 4_visualization.sh
# 可視化分析 (easymetagenome 環境)
# Alpha/Beta 多樣性 + 熱圖 + 堆疊圖
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
LOG_DIR="${LOG_DIR:-$WORK_DIR/log}"
LOG_FILE="${LOG_DIR}/viz_$(date +%Y%m%d_%H%M%S).log"

CONDA_BASE="${CONDA_BASE:-$HOME/miniconda3}"
DB_DIR="${DB_DIR:-$HOME/db}"
THREADS="${THREADS:-16}"
USE_CONDA="${USE_CONDA:-auto}"
AUTO_METADATA="${AUTO_METADATA:-0}"
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
echo "可視化分析 (easymetagenome)"               | tee -a "$LOG_FILE"
echo "Log 檔案: $LOG_FILE"                       | tee -a "$LOG_FILE"
echo "==========================================" | tee -a "$LOG_FILE"

log "工作目錄: $WORK_DIR"
log "結果目錄: $RESULT_DIR"

# 激活 conda（可選）
if [ "$USE_CONDA" != "0" ] && [ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]; then
    source "${CONDA_BASE}/etc/profile.d/conda.sh"
    log "激活分析環境..."
    ENV_ACTIVATED=""
    if conda activate easymetagenome 2>/dev/null; then
        ENV_ACTIVATED="easymetagenome"
    elif conda activate base 2>/dev/null; then
        ENV_ACTIVATED="base"
    fi

    if [ -z "$ENV_ACTIVATED" ]; then
        log_warn "無法激活 conda 環境，改用當前 Python"
    else
        log_ok "環境: $ENV_ACTIVATED"
    fi
elif [ "$USE_CONDA" = "1" ]; then
    log_err "找不到 conda: ${CONDA_BASE}/etc/profile.d/conda.sh"
    exit 1
else
    log "USE_CONDA=0 或 conda 缺失，使用當前 Python"
fi

# ==========================================
# 檢查必要檔案
# ==========================================

log_step "檢查必要檔案"

if [ ! -f "$METAPHLAN_DIR/taxonomy.tsv" ]; then
    log_err "找不到 taxonomy.tsv: $METAPHLAN_DIR/taxonomy.tsv"
    log "請先執行: ./1_main_analysis.sh"
    exit 1
fi
log_ok "taxonomy.tsv 已找到"

# 檢查 Python 套件（在 conda 環境內安裝，不用 --break-system-packages）
log "檢查 Python 套件..."
if "$PYTHON_BIN" -c "import pandas, matplotlib, numpy, scipy" 2>/dev/null; then
    log_ok "Python 套件已就緒"
else
    log_err "缺少 Python 套件。請在映像建置階段安裝 pandas/matplotlib/numpy/scipy/scikit-learn。"
    exit 1
fi

# ==========================================
# 自動生成 metadata.txt
# ==========================================

log_step "檢查 metadata.txt"

if [ ! -f "$RESULT_DIR/metadata.txt" ]; then
    if [ "$AUTO_METADATA" != "1" ]; then
        log_err "metadata.txt 不存在，且 AUTO_METADATA!=1，停止分析。"
        log "如要自動生成請設定 AUTO_METADATA=1"
        exit 1
    fi
    log_warn "metadata.txt 不存在，自動生成..."
    "$PYTHON_BIN" - "$METAPHLAN_DIR" "$RESULT_DIR" >>"$LOG_FILE" 2>&1 << 'PYEOF'
import sys, pandas as pd
metaphlan_dir = sys.argv[1]
result_dir    = sys.argv[2]
df = pd.read_csv(f'{metaphlan_dir}/taxonomy.tsv', sep='\t', index_col=0)
samples = [c.replace('_taxa', '') for c in df.columns]
with open(f'{result_dir}/metadata.txt', 'w') as f:
    f.write('#SampleID\tGroup\n')
    for i, s in enumerate(samples):
        grp = 'Group1' if i % 2 == 0 else 'Group2'
        f.write(f'{s}\t{grp}\n')
print(f"✓ 已自動生成 metadata.txt ({len(samples)} 個樣本)")
PYEOF
    log_warn "所有樣本預設已依序分配 Group1/Group2，如需修改分組請編輯: $RESULT_DIR/metadata.txt"
else
    log_ok "metadata.txt 已存在"
    log "內容:"
    cat "$RESULT_DIR/metadata.txt" | tee -a "$LOG_FILE"
fi

# ==========================================
# 執行 Python 可視化
# ==========================================

log_step "執行可視化分析"

"$PYTHON_BIN" - "$METAPHLAN_DIR" "$RESULT_DIR" >>"$LOG_FILE" 2>&1 << 'PYEOF'
import sys, os, glob
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np
from scipy.stats import entropy
from scipy.spatial.distance import braycurtis

METAPHLAN_DIR = sys.argv[1]
RESULT_DIR    = sys.argv[2]
os.chdir(METAPHLAN_DIR)

COLORS = ['#e6194b','#3cb44b','#ffe119','#4363d8','#f58231',
          '#911eb4','#42d4f4','#f032e6','#bfef45','#fabed4',
          '#469990','#dcbeff','#9A6324','#fffac8','#800000',
          '#aaffc3','#808000','#ffd8b1','#000075','#a9a9a9']
GROUP_COLORS = ['#e6194b','#4363d8','#3cb44b','#f58231','#911eb4',
                '#42d4f4','#f032e6','#ffe119','#469990','#800000']

print("  讀取 taxonomy.tsv...")
df = pd.read_csv('taxonomy.tsv', sep='\t', index_col=0)
df.columns = [c.replace('_taxa', '') for c in df.columns]
samples = list(df.columns)
n = len(samples)
print(f"  ✓ 樣本數: {n}  ({', '.join(samples)})")

meta_path = os.path.join(RESULT_DIR, 'metadata.txt')
meta = pd.read_csv(meta_path, sep='\t', comment='#', header=0, names=['SampleID', 'Group'])
meta = meta[meta['SampleID'].isin(samples)]
if len(meta) == 0:
    meta = pd.DataFrame({'SampleID': samples, 'Group': 'Group1'})
sample_group    = dict(zip(meta['SampleID'], meta['Group']))
groups          = meta['Group'].unique().tolist()
group_color_map = {g: GROUP_COLORS[i % len(GROUP_COLORS)] for i, g in enumerate(groups)}

def clean_name(n):
    last = n.split('|')[-1]
    return last.split('__', 1)[1].replace('_', ' ') if '__' in last else last

def get_level(pat, excl=None):
    m = df.index.str.contains(pat, regex=False)
    if excl:
        m = m & ~df.index.str.contains(excl, regex=False)
    s = df[m].copy()
    s.index = [clean_name(x) for x in s.index]
    return s[(s > 0).any(axis=1)]

phylum  = get_level('p__', 'c__')
genus   = get_level('g__', 's__')
species = get_level('s__')
print(f"  ✓ 門:{len(phylum)}  屬:{len(genus)}  種:{len(species)}")

# ---- Alpha 多樣性 ----
print("\n  計算 Alpha 多樣性...")
alpha_rows = []
for s in samples:
    data  = df[s][df[s] > 0]
    props = data / data.sum() if data.sum() > 0 else data
    alpha_rows.append({
        'SampleID': s,
        'Group':    sample_group.get(s, 'Group1'),
        'richness': int((species[s] > 0).sum()),
        'shannon':  round(float(entropy(props)), 4),
        'simpson':  round(float(1 - sum(props**2)), 4)
    })
alpha_df = pd.DataFrame(alpha_rows)
alpha_df.to_csv('alpha.txt', sep='\t', index=False)
print("  ✓ alpha.txt")
print(alpha_df.to_string(index=False))

def plot_alpha(metric, fname):
    fig, ax = plt.subplots(figsize=(max(5, n * 1.2 + 2), 5))
    colors = [group_color_map.get(g, '#888') for g in alpha_df['Group']]
    bars   = ax.bar(range(n), alpha_df[metric].values, color=colors, edgecolor='white', width=0.6)
    ax.set_xticks(range(n))
    ax.set_xticklabels(alpha_df['SampleID'], rotation=30, ha='right', fontsize=10)
    ax.set_ylabel(metric.capitalize(), fontsize=12)
    ax.set_title(f'{metric.capitalize()} Diversity', fontweight='bold')
    for bar, val in zip(bars, alpha_df[metric].values):
        ax.text(bar.get_x() + bar.get_width() / 2,
                bar.get_height() + bar.get_height() * 0.02,
                f'{val:.3f}', ha='center', fontsize=9)
    if len(groups) > 1:
        patches = [mpatches.Patch(color=group_color_map[g], label=g) for g in groups]
        ax.legend(handles=patches)
    ax.grid(axis='y', alpha=0.3, linestyle='--')
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    plt.tight_layout()
    plt.savefig(fname, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  ✓ {fname}")

plot_alpha('richness', 'boxplot_richness.pdf')
plot_alpha('shannon',  'boxplot_shannon.pdf')
plot_alpha('simpson',  'boxplot_simpson.pdf')

# ---- Beta 多樣性 PCoA ----
print("\n  Beta 多樣性 PCoA...")
if n >= 2:
    sp_mat   = species.T.reindex(columns=species.columns).fillna(0).values.astype(float)
    row_sums = sp_mat.sum(axis=1, keepdims=True)
    row_sums[row_sums == 0] = 1
    sp_mat   = sp_mat / row_sums
    dist = np.zeros((n, n))
    for i in range(n):
        for j in range(i + 1, n):
            d = braycurtis(sp_mat[i], sp_mat[j])
            dist[i][j] = dist[j][i] = d
    pd.DataFrame(dist, index=samples, columns=samples).to_csv('beta_bray.txt', sep='\t')

    H     = np.eye(n) - np.ones((n, n)) / n
    B     = -0.5 * H @ (dist**2) @ H
    evals, evecs = np.linalg.eigh(B)
    idx   = np.argsort(evals)[::-1]
    evals, evecs = evals[idx], evecs[:, idx]
    pos   = np.maximum(evals[:2], 0)
    coords = evecs[:, :2] * np.sqrt(pos)
    total  = sum(e for e in evals if e > 0)
    v1 = evals[0] / total * 100 if total > 0 else 0
    v2 = evals[1] / total * 100 if total > 0 else 0

    fig, ax = plt.subplots(figsize=(8, 7))
    for i, s in enumerate(samples):
        g = sample_group.get(s, 'Group1')
        c = group_color_map.get(g, '#888')
        ax.scatter(coords[i, 0], coords[i, 1], c=c, s=150, zorder=5,
                   edgecolors='white', linewidth=1.5)
        ax.annotate(s, (coords[i, 0], coords[i, 1]),
                    textcoords='offset points', xytext=(8, 5), fontsize=9)
    ax.set_xlabel(f'PC1 ({v1:.1f}%)', fontsize=12)
    ax.set_ylabel(f'PC2 ({v2:.1f}%)', fontsize=12)
    ax.set_title('PCoA - Bray-Curtis Distance', fontweight='bold', fontsize=13)
    ax.axhline(0, color='gray', lw=0.5, ls='--', alpha=0.5)
    ax.axvline(0, color='gray', lw=0.5, ls='--', alpha=0.5)
    ax.grid(alpha=0.2)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    if len(groups) > 1:
        patches = [mpatches.Patch(color=group_color_map[g], label=g) for g in groups]
        ax.legend(handles=patches)
    plt.tight_layout()
    plt.savefig('pcoa.bray_curtis.pdf', dpi=300, bbox_inches='tight')
    plt.close()
    print("  ✓ pcoa.bray_curtis.pdf")
else:
    print("  ⚠ 樣本數 < 2，跳過 PCoA")

# ---- 熱圖 ----
print("\n  繪製熱圖...")
def plot_heatmap(data, level_name, fname, top_n=25):
    if data.empty:
        print(f"  ⚠ {level_name} 無數據，跳過")
        return
    top = data.copy()
    top['mean'] = top.mean(axis=1)
    top = top.sort_values('mean', ascending=False).head(top_n).drop('mean', axis=1)
    fig, ax = plt.subplots(figsize=(max(6, n * 1.2 + 3), max(6, len(top) * 0.4)))
    im = ax.imshow(top.values, cmap='YlOrRd', aspect='auto')
    ax.set_xticks(range(n))
    ax.set_xticklabels(top.columns, rotation=30, ha='right', fontsize=10)
    ax.set_yticks(range(len(top)))
    ax.set_yticklabels(top.index, fontsize=9)
    ax.set_title(f'Top {len(top)} {level_name}', fontweight='bold', fontsize=13)
    plt.colorbar(im, ax=ax, label='Relative Abundance (%)', shrink=0.8)
    if n <= 10 and len(top) <= 30:
        for i in range(len(top)):
            for j in range(n):
                val = top.values[i, j]
                tc  = 'white' if val > top.values.max() * 0.6 else 'black'
                ax.text(j, i, f'{val:.1f}', ha='center', va='center', fontsize=7, color=tc)
    plt.tight_layout()
    plt.savefig(fname, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  ✓ {fname}")

plot_heatmap(phylum,  'Phylum',  'heatmap_Phylum.pdf',  15)
plot_heatmap(genus,   'Genus',   'heatmap_Genus.pdf',   25)
plot_heatmap(species, 'Species', 'heatmap_Species.pdf', 25)

# ---- 堆疊條形圖 ----
print("\n  繪製堆疊條形圖...")
def plot_stacked(data, level_name, fname, top_n=10):
    if data.empty:
        print(f"  ⚠ {level_name} 無數據，跳過")
        return
    top = data.copy()
    top['mean']  = top.mean(axis=1)
    top_taxa     = top.sort_values('mean', ascending=False).head(top_n).drop('mean', axis=1)
    others       = pd.DataFrame([100 - top_taxa.sum(axis=0)], index=['Others'])
    plot_data    = pd.concat([top_taxa, others])
    fig, ax      = plt.subplots(figsize=(max(6, n * 1.5 + 2), 7))
    bottom       = np.zeros(n)
    for i, (taxon, row) in enumerate(plot_data.iterrows()):
        vals = row[samples].values.astype(float)
        ax.bar(range(n), vals, bottom=bottom, label=taxon,
               color=COLORS[i % len(COLORS)], edgecolor='white', linewidth=0.5)
        bottom += vals
    ax.set_xticks(range(n))
    ax.set_xticklabels(samples, rotation=30, ha='right', fontsize=10)
    ax.set_ylabel('Relative Abundance (%)', fontsize=12)
    ax.set_title(f'{level_name} Composition', fontweight='bold', fontsize=13)
    ax.set_ylim(0, 105)
    ax.legend(bbox_to_anchor=(1.02, 1), loc='upper left', fontsize=9)
    ax.grid(axis='y', alpha=0.3, linestyle='--')
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    plt.tight_layout()
    plt.savefig(fname, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  ✓ {fname}")

plot_stacked(phylum,  'Phylum',  'stacked_Phylum.pdf',  10)
plot_stacked(genus,   'Genus',   'stacked_Genus.pdf',   15)
plot_stacked(species, 'Species', 'stacked_Species.pdf', 15)

print()
print("=" * 60)
print("✅ 可視化分析完成！")
print("=" * 60)
for f in sorted(glob.glob('*.pdf')):
    size = os.path.getsize(f) // 1024
    print(f"  📊 {f} ({size} KB)")
print()
print("Alpha 多樣性摘要：")
print(alpha_df.to_string(index=False))
PYEOF

VIZ_EXIT=$?

if [ $VIZ_EXIT -eq 0 ]; then
    log_ok "Python 可視化腳本執行完成"
else
    log_err "Python 可視化腳本失敗（exit code: $VIZ_EXIT），查看 log: $LOG_FILE"
fi

# ==========================================
# 最終摘要
# ==========================================

log_step "✅ 可視化分析完成！"

PDF_COUNT=$(ls "$METAPHLAN_DIR"/*.pdf 2>/dev/null | wc -l)
log "產生 PDF 檔案: $PDF_COUNT 個"
for f in "$METAPHLAN_DIR"/*.pdf; do
    [ -f "$f" ] && log "  📊 $(basename "$f")"
done

log ""
log "【完整 Log】$LOG_FILE"
log "【圖表位置】$METAPHLAN_DIR"
log "【複製到家目錄】cp $METAPHLAN_DIR/*.pdf ~/"
