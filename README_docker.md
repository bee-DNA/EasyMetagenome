# EasyMetagenome Docker 新手完整教學

本文件給「沒有生信與 Docker 基礎」的使用者，照做即可完成：

1. 建立掛載資料夾
2. 設定 `.env`
3. 下載所需資料庫到掛載路徑
4. 執行完整流程
5. 檢查結果與重跑單一模組

## 0. 先知道這個流程在做什麼

`docker compose up -d` 會依序執行：

1. `1_main_analysis.sh`
2. `1.5_checkm2_analysis.sh`
3. `2_humann_analysis.sh`
4. `3_lefse_analysis.sh`
5. `4_visualization.sh`
6. `5_eggnog_analysis.sh`

注意：

- `docker compose up -d` 會啟動流程，但不會自動幫你下載所有大型資料庫。
- 你要先完成「第 4 章：資料庫下載」，再跑完整流程最穩定。

## 1. 系統需求（建議）

- 作業系統：Windows 10/11、Linux、macOS
- Docker Desktop（含 Compose plugin）
- RAM：至少 16 GB（建議 32 GB）
- 磁碟：至少 100 GB 可用空間（建議更多）

## 2. 下載專案並進入資料夾

如果你已經有專案，直接進入專案根目錄即可。

```bash
cd EasyMetagenome
```

## 3. 建立掛載資料夾與 `.env`

### 3.1 建立主資料夾（Windows PowerShell）

以下示範用 `D:\EasyMeta` 作為掛載根目錄，你可自行改路徑。

```powershell
$ROOT = "D:/EasyMeta"
New-Item -ItemType Directory -Force -Path `
  "$ROOT/work", `
  "$ROOT/work/seq", `
  "$ROOT/work/result", `
  "$ROOT/work/temp", `
  "$ROOT/work/log", `
  "$ROOT/db", `
  "$ROOT/db/metaphlan4", `
  "$ROOT/db/humann4", `
  "$ROOT/db/humann4/chocophlan", `
  "$ROOT/db/humann4/uniref", `
  "$ROOT/db/checkm2", `
  "$ROOT/db/eggnog" | Out-Null
```

### 3.2（可選）Linux/macOS 建立方式

```bash
ROOT="$HOME/easymeta"
mkdir -p \
  "$ROOT/work/seq" \
  "$ROOT/work/result" \
  "$ROOT/work/temp" \
  "$ROOT/work/log" \
  "$ROOT/db/metaphlan4" \
  "$ROOT/db/humann4/chocophlan" \
  "$ROOT/db/humann4/uniref" \
  "$ROOT/db/checkm2" \
  "$ROOT/db/eggnog"
```

### 3.3 建立 `.env`

1. 複製範本：

```bash
cp .env.example .env
```

2. 依你的路徑修改 `.env`（Windows 範例）：

```dotenv
WORK_DIR=D:/EasyMeta/work
SEQ_DIR=D:/EasyMeta/work/seq
RESULT_DIR=D:/EasyMeta/work/result
TEMP_DIR=D:/EasyMeta/work/temp
LOG_DIR=D:/EasyMeta/work/log
DB_DIR=D:/EasyMeta/db
THREADS=16
AUTO_METADATA=0
```

建議：

- Windows 路徑請用正斜線 `/`。
- 路徑不要包含空白字元。

## 4. 下載資料庫（必做）

先建 image：

```bash
docker compose build
```

### 4.1 MetaPhlAn4 DB

```bash
docker compose run --rm main bash -lc "metaphlan --install --db_dir /workspace/db/metaphlan4"
```

### 4.2 HUMAnN DB（chocophlan + uniref）

```bash
docker compose run --rm humann bash -lc "humann_databases --download chocophlan full /workspace/db/humann4"
docker compose run --rm humann bash -lc "humann_databases --download uniref uniref90_diamond /workspace/db/humann4"
```

### 4.3 CheckM2 DB

```bash
docker compose run --rm checkm2 bash -lc "checkm2 database --download --path /workspace/db/checkm2"
```

### 4.4 eggNOG DB（建議完整下載）

eggNOG 檔案很大，通常會花較久時間。以下命令會下載到 `DB_DIR/eggnog`。

```bash
docker compose run --rm eggnog bash -lc "python - <<'PY'
import os
import urllib.request

base = 'http://eggnog6.embl.de/download/emapperdb-5.0.2'
out = '/workspace/db/eggnog'
os.makedirs(out, exist_ok=True)

files = [
    'eggnog.db.gz',
    'eggnog_proteins.dmnd.gz',
    'eggnog.taxa.tar.gz',
]

for f in files:
    url = f'{base}/{f}'
    dst = os.path.join(out, f)
    print(f'DOWNLOAD: {url}')
    urllib.request.urlretrieve(url, dst)
    print(f'SAVED: {dst}')
PY"
```

下載後解壓兩個 `.gz`：

```bash
docker compose run --rm eggnog bash -lc "cd /workspace/db/eggnog && gzip -dc eggnog.db.gz > eggnog.db && gzip -dc eggnog_proteins.dmnd.gz > eggnog_proteins.dmnd"
```

### 4.5 確認 DB 檔案存在

```bash
docker compose run --rm eggnog bash -lc "ls -lh /workspace/db/eggnog"
docker compose run --rm humann bash -lc "ls -lh /workspace/db/humann4"
docker compose run --rm checkm2 bash -lc "ls -lh /workspace/db/checkm2"
```

## 5. 準備輸入 FASTQ

把 paired-end 檔案放到 `SEQ_DIR`，命名格式如下：

- `SampleA_1.fastq` 與 `SampleA_2.fastq`
- 或 `SampleA_1.fq.gz` 與 `SampleA_2.fq.gz`

可用以下命令檢查：

```bash
docker compose run --rm main bash -lc "ls -lh /workspace/seq"
```

## 6. 一鍵跑完整流程

```bash
docker compose up -d
```

查看狀態：

```bash
docker compose ps
```

追蹤全部 log：

```bash
docker compose logs -f
```

只看某模組（例如 eggnog）：

```bash
docker compose logs -f eggnog
```

## 7. 如何判斷跑完

以下條件代表流程完成：

1. `docker compose ps` 顯示各服務 `Exited (0)`
2. `pipeline-runner` 顯示完成訊息
3. `RESULT_DIR`、`TEMP_DIR`、`LOG_DIR` 有對應輸出檔

重點輸出通常在：

- `RESULT_DIR/metaphlan4/taxonomy.tsv`
- `RESULT_DIR/humann4/`
- `RESULT_DIR/checkm2/quality_report.tsv`
- `RESULT_DIR/eggnog/*.emapper.annotations`

## 8. 單模組重跑（失敗時常用）

```bash
bash docker/run.sh main
bash docker/run.sh checkm2
bash docker/run.sh humann
bash docker/run.sh lefse
bash docker/run.sh visualization
bash docker/run.sh eggnog
```

看 log：

```bash
bash docker/run.sh logs
bash docker/run.sh logs main
```

## 9. 常見問題（新手版）

1. `docker compose up -d` 很快結束但沒有結果

- 多半是前一模組失敗，請先看：
  - `docker compose ps`
  - `docker compose logs -f <service>`

2. 出現資料庫不存在錯誤

- 先確認 `.env` 的 `DB_DIR` 是否正確。
- 再確認子資料夾是否存在：
  - `metaphlan4`
  - `humann4/chocophlan`
  - `humann4/uniref`
  - `checkm2`
  - `eggnog`

3. eggNOG 被跳過

- 通常是 `eggnog.db` 或 `eggnog_proteins.dmnd` 不存在或檔案太小。
- 重新執行第 4.4 下載與解壓步驟。

4. 記憶體不足（MEGAHIT/HUMAnN/CheckM2）

- 提高 Docker Desktop CPU/RAM。
- 或把 `.env` 的 `THREADS` 調小（例如 8）。

## 10. 建議的第一次實作流程（最穩）

1. 完成第 3 章掛載與 `.env`
2. 完成第 4 章所有 DB 下載
3. 放入 1-2 組小型 FASTQ 測試資料
4. `docker compose up -d`
5. 確認 `Exited (0)` 後再放完整正式資料

照這份教學做，可在全新機器上完成完整部署、資料庫掛載與資料分析流程。
