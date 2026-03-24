# EasyMetagenome Docker Ubuntu 部署完整教學

本文件以 Ubuntu 22.04/24.04 為主，給「沒有生信與 Docker 基礎」的使用者。照做可完成：

1. 安裝 Docker 與 Compose
2. 建立掛載資料夾與 `.env`
3. 下載所需資料庫到掛載路徑（詳細）
4. 執行完整流程
5. 檢查結果與重跑單一模組

## 0. 先了解流程順序

`docker compose up -d` 會依序執行：

1. `1_main_analysis.sh`
2. `1.5_checkm2_analysis.sh`
3. `2_humann_analysis.sh`
4. `3_lefse_analysis.sh`
5. `4_visualization.sh`
6. `5_eggnog_analysis.sh`

注意：

- `docker compose up -d` 只會啟動流程，不會自動下載所有大型資料庫。
- 請先完成第 6 章「資料庫下載」，再跑完整流程最穩定。

## 1. 系統需求（建議）

- 作業系統：Ubuntu 22.04 或 24.04
- Docker Engine + Docker Compose plugin
- RAM：至少 16 GB（建議 32 GB）
- 磁碟：至少 100 GB 可用空間（建議 200 GB 以上）

## 2. Ubuntu 安裝 Docker 與 Compose

如果你已安裝，可跳到第 3 章。

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

把目前使用者加入 docker 群組（避免每次都要 `sudo`）：

```bash
sudo usermod -aG docker $USER
newgrp docker
```

檢查版本：

```bash
docker --version
docker compose version
```

## 3. 取得專案並進入目錄

```bash
cd EasyMetagenome
```

## 4. 建立掛載資料夾與 `.env`

### 4.1 建立主資料夾（Ubuntu）

以下示範使用 `$HOME/easymeta` 作為掛載根目錄。

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

### 4.2 建立 `.env`

```bash
cp .env.example .env
```

編輯 `.env`（Ubuntu 範例）：

```dotenv
WORK_DIR=/home/<你的使用者名稱>/easymeta/work
SEQ_DIR=/home/<你的使用者名稱>/easymeta/work/seq
RESULT_DIR=/home/<你的使用者名稱>/easymeta/work/result
TEMP_DIR=/home/<你的使用者名稱>/easymeta/work/temp
LOG_DIR=/home/<你的使用者名稱>/easymeta/work/log
DB_DIR=/home/<你的使用者名稱>/easymeta/db
THREADS=16
AUTO_METADATA=0
```

建議：

- 路徑請用絕對路徑。
- 路徑避免空白字元。
- `THREADS` 建議先設為 CPU 邏輯核心數的一半到 2/3。

### 4.3 先檢查掛載路徑是否正確

```bash
docker compose config
```

看到 `WORK_DIR`、`DB_DIR` 等變數有正確展開，再往下進行。

## 5. 建置映像

```bash
docker compose build
```

第一次建置會花一些時間。

## 6. 下載資料庫（必做，詳細版）

本章是成功率關鍵。建議照順序做，下載中斷可重跑同一條命令。

### 6.0 先確認容器內看得到 DB 掛載路徑

```bash
docker compose run --rm main bash -lc "ls -lah /workspace/db"
```

你應該能看到：`metaphlan4`、`humann4`、`checkm2`、`eggnog`。

### 6.1 MetaPhlAn4 DB

下載：

```bash
docker compose run --rm main bash -lc "metaphlan --install --db_dir /workspace/db/metaphlan4"
```

檢查：

```bash
docker compose run --rm main bash -lc "ls -lah /workspace/db/metaphlan4"
```

若網路中斷，直接重跑安裝命令即可。

### 6.2 HUMAnN DB（chocophlan + uniref）

下載 `chocophlan`：

```bash
docker compose run --rm humann bash -lc "humann_databases --download chocophlan full /workspace/db/humann4"
```

下載 `uniref90_diamond`：

```bash
docker compose run --rm humann bash -lc "humann_databases --download uniref uniref90_diamond /workspace/db/humann4"
```

檢查：

```bash
docker compose run --rm humann bash -lc "ls -lah /workspace/db/humann4"
docker compose run --rm humann bash -lc "du -sh /workspace/db/humann4/*"
```

若下載慢或失敗：

- 先重跑同一命令，通常會續傳或跳過已完成檔案。
- 避開尖峰時段再下載。

### 6.3 CheckM2 DB

下載：

```bash
docker compose run --rm checkm2 bash -lc "checkm2 database --download --path /workspace/db/checkm2"
```

檢查：

```bash
docker compose run --rm checkm2 bash -lc "ls -lah /workspace/db/checkm2"
```

### 6.4 eggNOG DB（重點，最詳細）

eggNOG 通常是最耗時、最容易因網路中斷失敗的部分。

1. 先下載壓縮檔（含斷線續傳）：

```bash
docker compose run --rm eggnog bash -lc "set -e
cd /workspace/db/eggnog
base='http://eggnog6.embl.de/download/emapperdb-5.0.2'
for f in eggnog.db.gz eggnog_proteins.dmnd.gz eggnog.taxa.tar.gz; do
  echo "[DOWNLOAD] $f"
  wget -c -O "$f" "$base/$f"
done
ls -lh
"
```

2. 解壓核心資料檔：

```bash
docker compose run --rm eggnog bash -lc "set -e
cd /workspace/db/eggnog
gzip -dc eggnog.db.gz > eggnog.db
gzip -dc eggnog_proteins.dmnd.gz > eggnog_proteins.dmnd
ls -lh eggnog.db eggnog_proteins.dmnd eggnog.taxa.tar.gz
"
```

3. 快速完整性檢查：

```bash
docker compose run --rm eggnog bash -lc "set -e
cd /workspace/db/eggnog
test -s eggnog.db
test -s eggnog_proteins.dmnd
echo 'eggNOG core DB files look OK.'
du -sh .
"
```

4. 若要解開 `eggnog.taxa.tar.gz`：

```bash
docker compose run --rm eggnog bash -lc "set -e
cd /workspace/db/eggnog
mkdir -p taxa
tar -xzf eggnog.taxa.tar.gz -C taxa
ls -lah taxa | head
"
```

常見問題處理：

- `wget` 失敗：重跑同一命令，`-c` 會嘗試續傳。
- 下載檔案大小明顯異常（過小）：刪除該檔後重抓。
- 解壓時 `unexpected end of file`：代表 `.gz` 檔不完整，重抓該檔。

### 6.5 一次檢查所有 DB 是否就緒

```bash
docker compose run --rm main bash -lc "set -e
echo '[metaphlan4]'
ls -lah /workspace/db/metaphlan4 | head
echo
echo '[humann4]'
ls -lah /workspace/db/humann4
echo
echo '[checkm2]'
ls -lah /workspace/db/checkm2 | head
echo
echo '[eggnog]'
ls -lah /workspace/db/eggnog | grep -E 'eggnog.db|eggnog_proteins.dmnd|eggnog.taxa.tar.gz' || true
"
```

## 7. 準備輸入 FASTQ

把 paired-end 檔案放到 `SEQ_DIR`，命名格式如下：

- `SampleA_1.fastq` 與 `SampleA_2.fastq`
- 或 `SampleA_1.fq.gz` 與 `SampleA_2.fq.gz`

檢查：

```bash
docker compose run --rm main bash -lc "ls -lh /workspace/seq"
```

## 8. 一鍵跑完整流程

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

## 9. 如何判斷跑完

以下條件代表流程完成：

1. `docker compose ps` 顯示各服務 `Exited (0)`
2. `pipeline-runner` 顯示完成訊息
3. `RESULT_DIR`、`TEMP_DIR`、`LOG_DIR` 有輸出檔

重點輸出通常在：

- `RESULT_DIR/metaphlan4/taxonomy.tsv`
- `RESULT_DIR/humann4/`
- `RESULT_DIR/checkm2/quality_report.tsv`
- `RESULT_DIR/eggnog/*.emapper.annotations`

## 10. 單模組重跑（失敗時常用）

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

## 11. 常見問題（Ubuntu）

1. `permission denied`（通常是掛載資料夾權限）

```bash
sudo chown -R $USER:$USER "$HOME/easymeta"
chmod -R u+rwX "$HOME/easymeta"
```

2. `docker: permission denied`（使用者未加入 docker 群組）

- 重新執行第 2 章 `usermod -aG docker $USER`
- 重新登入或執行 `newgrp docker`

3. `docker compose up -d` 很快結束但沒結果

- 先看 `docker compose ps`
- 再看 `docker compose logs -f <service>`

4. eggNOG 被跳過

- 多半是 `eggnog.db` 或 `eggnog_proteins.dmnd` 不存在或損毀。
- 回到第 6.4 重新下載與解壓。

5. 記憶體不足（MEGAHIT/HUMAnN/CheckM2）

- 把 `.env` 的 `THREADS` 調小（例如 8）。
- 先用小資料集測試完整流程，再放正式資料。

## 12. 建議第一次實作流程（最穩）

1. 完成第 2 章 Docker 安裝
2. 完成第 4 章掛載與 `.env`
3. 完成第 6 章所有 DB 下載與檢查
4. 放 1 到 2 組小型 FASTQ 測試
5. `docker compose up -d`
6. 確認全部 `Exited (0)` 後，再放完整正式資料

照這份 Ubuntu 教學做，可在全新機器上完成完整部署、資料庫掛載與資料分析流程。
