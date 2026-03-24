#!/bin/bash

# ==========================================
# setup_easymetagenome_stable.sh
# 穩定版 EasyMetagenome 環境設置
# 分步驟安裝，避免衝突
# ==========================================

set -e

echo "=========================================="
echo "EasyMetagenome 環境設置（穩定版）"
echo "=========================================="
echo ""

soft=~/miniconda3
source "${soft}/etc/profile.d/conda.sh"

# ==========================================
# 清理舊環境
# ==========================================

echo "【準備工作】"
if conda env list | grep -q "^easymetagenome "; then
    echo "發現舊環境 easymetagenome"
    read -p "是否刪除? (y/N): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        conda deactivate 2>/dev/null || true
        conda env remove -n easymetagenome -y
        echo "✓ 已刪除舊環境"
    fi
fi
echo ""

# ==========================================
# 使用 mamba 加速（推薦）
# ==========================================

echo "【步驟 1】安裝 mamba 加速器..."
conda install mamba -n base -c conda-forge -y 2>/dev/null || {
    echo "⚠ mamba 安裝失敗，使用 conda"
    USE_MAMBA=false
}

if command -v mamba &> /dev/null; then
    echo "✓ 將使用 mamba 安裝（更快更穩定）"
    INSTALLER="mamba"
else
    echo "⚠ 使用 conda 安裝"
    INSTALLER="conda"
fi
echo ""

# ==========================================
# 創建環境（分步驟安裝）
# ==========================================

echo "【步驟 2】創建基礎環境..."
$INSTALLER create -n easymetagenome python=3.10 -y
conda activate easymetagenome
echo "✓ 環境已創建"
echo ""

# ==========================================
# 第一組：基礎工具
# ==========================================

echo "【步驟 3】安裝基礎分析工具..."

echo "  - 質控工具..."
$INSTALLER install -c bioconda fastp -y

echo "  - 組裝工具..."
$INSTALLER install -c bioconda megahit -y

echo "  - 基因預測..."
$INSTALLER install -c bioconda prodigal -y

echo "  - 比對工具..."
$INSTALLER install -c bioconda bowtie2 samtools -y

echo "✓ 基礎工具完成"
echo ""

# ==========================================
# 第二組：物種分類
# ==========================================

echo "【步驟 4】安裝物種分類工具..."

echo "  - MetaPhlAn4..."
$INSTALLER install -c bioconda metaphlan -y

echo "  - Kraken2..."
$INSTALLER install -c bioconda kraken2 -y 2>/dev/null || {
    echo "  ⚠ Kraken2 安裝失敗（可選工具）"
}

echo "✓ 物種分類工具完成"
echo ""

# ==========================================
# 第三組：Binning
# ==========================================

echo "【步驟 5】安裝 Binning 工具..."

echo "  - MetaBAT2..."
$INSTALLER install -c bioconda metabat2 -y

echo "  - CheckM..."
$INSTALLER install -c bioconda checkm-genome -y 2>/dev/null || {
    echo "  ⚠ CheckM 安裝失敗（將跳過）"
}

echo "✓ Binning 工具完成"
echo ""

# ==========================================
# 第四組：功能註釋
# ==========================================

echo "【步驟 6】安裝功能註釋工具..."

echo "  - eggNOG-mapper..."
$INSTALLER install -c bioconda eggnog-mapper -y 2>/dev/null || {
    echo "  ⚠ eggNOG-mapper 安裝失敗（將跳過）"
}

echo "✓ 功能註釋工具完成"
echo ""

# ==========================================
# 第五組：差異分析
# ==========================================

echo "【步驟 7】安裝差異分析工具..."

echo "  - LEfSe..."
$INSTALLER install -c bioconda lefse -y 2>/dev/null || {
    echo "  ⚠ LEfSe 安裝失敗"
    echo "  嘗試從 conda-forge..."
    conda install -c conda-forge -c bioconda lefse -y 2>/dev/null || {
        echo "  ⚠ LEfSe 安裝失敗（將用 Python 替代方案）"
    }
}

echo "✓ 差異分析工具完成"
echo ""

# ==========================================
# 第六組：R 環境
# ==========================================

echo "【步驟 8】安裝 R 環境..."

echo "  - R 基礎..."
$INSTALLER install -c conda-forge r-base=4.3 -y

echo "  - R 統計套件..."
$INSTALLER install -c conda-forge \
    r-vegan \
    r-ggplot2 \
    r-pheatmap \
    r-reshape2 \
    r-dplyr \
    -y 2>/dev/null || {
    echo "  ⚠ 部分 R 套件安裝失敗，將用 R 內建安裝"
}

echo "✓ R 環境完成"
echo ""

# ==========================================
# 第七組：Python 科學計算
# ==========================================

echo "【步驟 9】安裝 Python 套件..."

pip install --no-cache-dir --quiet \
    pandas \
    numpy \
    scipy \
    matplotlib \
    seaborn \
    scikit-learn \
    biopython \
    matplotlib-venn

echo "✓ Python 套件完成"
echo ""

# ==========================================
# HUMAnN 獨立環境
# ==========================================

echo "【步驟 10】創建 HUMAnN 獨立環境..."

conda deactivate
if ! conda env list | grep -q "^humann4 "; then
    $INSTALLER create -n humann4 python=3.10 -y
    conda activate humann4
    $INSTALLER install -c bioconda humann metaphlan -y
    echo "✓ HUMAnN 環境已創建"
else
    echo "✓ HUMAnN 環境已存在"
fi

conda activate easymetagenome
echo ""

# ==========================================
# 驗證安裝
# ==========================================

echo "=========================================="
echo "【驗證安裝】"
echo "=========================================="
echo ""

# 創建驗證報告
REPORT_FILE=~/easymetagenome_install_report.txt
echo "EasyMetagenome 安裝報告" > $REPORT_FILE
echo "日期: $(date)" >> $REPORT_FILE
echo "========================================" >> $REPORT_FILE
echo "" >> $REPORT_FILE

echo "✓ 已安裝的工具:" | tee -a $REPORT_FILE
echo "" | tee -a $REPORT_FILE

check_tool() {
    local tool=$1
    local name=$2
    if command -v $tool &> /dev/null; then
        echo "  ✓ $name" | tee -a $REPORT_FILE
        return 0
    else
        echo "  ❌ $name" | tee -a $REPORT_FILE
        return 1
    fi
}

echo "基礎工具:" | tee -a $REPORT_FILE
check_tool fastp "FastP (質控)"
check_tool megahit "MEGAHIT (組裝)"
check_tool prodigal "Prodigal (基因預測)"
check_tool bowtie2 "Bowtie2 (比對)"
check_tool samtools "Samtools (BAM處理)"

echo "" | tee -a $REPORT_FILE
echo "物種分類:" | tee -a $REPORT_FILE
check_tool metaphlan "MetaPhlAn4"
check_tool kraken2 "Kraken2"

echo "" | tee -a $REPORT_FILE
echo "Binning:" | tee -a $REPORT_FILE
check_tool metabat2 "MetaBAT2"
check_tool checkm "CheckM"

echo "" | tee -a $REPORT_FILE
echo "功能註釋:" | tee -a $REPORT_FILE
check_tool emapper.py "eggNOG-mapper"

echo "" | tee -a $REPORT_FILE
echo "統計分析:" | tee -a $REPORT_FILE
check_tool lefse-format_input.py "LEfSe"
check_tool Rscript "R"

echo "" | tee -a $REPORT_FILE
echo "Python套件:" | tee -a $REPORT_FILE
python3 -c "import pandas, numpy, scipy, matplotlib, seaborn, sklearn" 2>/dev/null && \
    echo "  ✓ 所有必需套件" | tee -a $REPORT_FILE || \
    echo "  ❌ 部分套件缺失" | tee -a $REPORT_FILE

echo "" | tee -a $REPORT_FILE
echo "========================================" | tee -a $REPORT_FILE

# ==========================================
# 創建快速啟動腳本
# ==========================================

cat > ~/activate_easy.sh << 'ACTIVATE'
#!/bin/bash
source ~/miniconda3/etc/profile.d/conda.sh
conda activate easymetagenome
echo "✓ EasyMetagenome 環境已激活"
ACTIVATE

chmod +x ~/activate_easy.sh

# ==========================================
# 最終說明
# ==========================================

echo ""
echo "=========================================="
echo "✅ 安裝完成！"
echo "=========================================="
echo ""

echo "【安裝報告】已保存至: $REPORT_FILE"
echo ""

echo "【快速開始】"
echo ""
echo "1. 激活環境:"
echo "   source ~/activate_easy.sh"
echo "   # 或"
echo "   conda activate easymetagenome"
echo ""

echo "2. 下載 MetaPhlAn4 資料庫 (必需):"
echo "   conda activate easymetagenome"
echo "   metaphlan --install --bowtie2db ~/db/metaphlan4"
echo ""

echo "3. 開始分析:"
echo "   cd /your/data/directory"
echo "   ./1pipeline_full.sh"
echo ""

echo "【缺少的工具】"
echo ""
if ! command -v checkm &> /dev/null; then
    echo "  - CheckM (基因組質量評估)"
    echo "    可選，如需要請單獨安裝: conda install -c bioconda checkm-genome"
fi

if ! command -v kraken2 &> /dev/null; then
    echo "  - Kraken2 (快速分類)"
    echo "    可選，如需要請單獨安裝: conda install -c bioconda kraken2"
fi

if ! command -v emapper.py &> /dev/null; then
    echo "  - eggNOG-mapper (功能註釋)"
    echo "    可選，如需要請單獨安裝: conda install -c bioconda eggnog-mapper"
fi

if ! command -v lefse-format_input.py &> /dev/null; then
    echo "  - LEfSe (差異分析)"
    echo "    已有替代方案，不影響使用"
fi

echo ""
echo "【磁碟空間需求】"
echo "  - 軟體環境: ~5-8 GB"
echo "  - MetaPhlAn4 資料庫: ~15 GB (必需)"
echo "  - 其他資料庫: ~150 GB (可選)"
echo ""

echo "=========================================="
echo ""