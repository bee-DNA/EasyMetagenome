# EasyMetagenome Docker 新環境啟動手冊（你已經有 portable tar）

這份文件是給「你已經有 `easymetagenome_allinone_portable.tar`」的情境。  
重點只有三件事：

1. 建立正確資料夾
2. 把正確檔案放到正確位置
3. 啟動並確認結果輸出

---

## 1. 先決條件

- 作業系統：Ubuntu 22.04 / 24.04（其他 Linux 也可）
- 已安裝 Docker + Docker Compose plugin

檢查：

```bash
docker --version
docker compose version
```

---

## 2. 專案與資料夾初始化

進入專案：

```bash
cd EasyMetagenome
```

建立 `.env`：

```bash
cp .env.example .env
```

建立掛載根目錄（範例用 `$HOME/easymeta`）：

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

---

## 3. 你最需要的目錄地圖（放檔規則）

```text
$ROOT/
├─ work/
│  ├─ seq/         # 你的分析輸入 FASTQ 放這裡
│  ├─ result/      # 分析結果輸出在這裡
│  ├─ temp/        # 中間檔（可很大）
│  └─ log/         # 每一步驟 log
└─ db/
   ├─ metaphlan4/  # MetaPhlAn DB
   ├─ humann4/
   │  ├─ chocophlan/
   │  └─ uniref/
   ├─ checkm2/
   └─ eggnog/
```

### 3.1 你的分析檔案要放哪裡

放在：`$ROOT/work/seq/`

檔名格式（paired-end）：

- `SampleA_1.fastq` + `SampleA_2.fastq`
- `SampleA_1.fq.gz` + `SampleA_2.fq.gz`

不符合 `*_1` / `*_2` 配對規則，流程會抓不到樣本。

如果你要自訂分組（建議），請放：

- `$ROOT/work/result/metadata.txt`

格式（Tab 分隔）：

```text
#SampleID	Group
SampleA	Control
SampleB	Treatment
```

`SampleID` 必須和 FASTQ 檔名前綴一致（例如 `SampleA_1.fq.gz` 的 `SampleA`）。

### 3.2 你的結果會出現在哪裡

主結果目錄：`$ROOT/work/result/`

常見子目錄：

- `metaphlan4/`：物種組成與可視化圖
- `humann4/`：功能分析結果
- `checkm2/`：bin 品質評估
- `differential/`：LEfSe 與差異分析
- `eggnog/`：eggNOG 註釋結果

### 3.3 Log 在哪裡

`$ROOT/work/log/`  
例如：`pipeline_*.log`、`lefse_*.log`、`viz_*.log`

---

## 4. `.env` 要怎麼填

把 `.env` 改成你的絕對路徑（以下是範例）：

```dotenv
WORK_DIR=/home/<user>/easymeta/work
SEQ_DIR=/home/<user>/easymeta/work/seq
RESULT_DIR=/home/<user>/easymeta/work/result
TEMP_DIR=/home/<user>/easymeta/work/temp
LOG_DIR=/home/<user>/easymeta/work/log
DB_DIR=/home/<user>/easymeta/db
THREADS=16
AUTO_METADATA=0
```

檢查設定是否生效：

```bash
docker compose -f docker-compose.portable.yml config
```

---

## 5. 你有 tar 時的啟動步驟

載入 image：

```bash
bash docker/run-portable.sh load easymetagenome_allinone_portable.tar
```

執行完整流程：

```bash
bash docker/run-portable.sh run
```

只跑單一模組：

```bash
bash docker/run-portable.sh stage main
bash docker/run-portable.sh stage checkm2
bash docker/run-portable.sh stage humann
bash docker/run-portable.sh stage lefse
bash docker/run-portable.sh stage visualization
bash docker/run-portable.sh stage eggnog
```

---

## 6. 如何判斷「有成功啟動」

看容器狀態：

```bash
docker compose -f docker-compose.portable.yml ps
```

看 log 是否持續更新：

```bash
ls -lah "$ROOT/work/log"
tail -f "$ROOT/work/log"/pipeline_*.log
```

至少要看到：

1. 有新 log 檔案產生
2. 流程有進入各階段腳本
3. `result` 目錄開始出現輸出檔案

---

## 7. 資料庫檢查（很重要）

portable tar 包含工具環境，不包含所有大型資料庫。  
如果 DB 沒準備好，部分模組會被跳過或失敗。

快速檢查 DB 目錄是否有內容：

```bash
ls -lah "$ROOT/db/metaphlan4" | head
ls -lah "$ROOT/db/humann4/chocophlan" | head
ls -lah "$ROOT/db/humann4/uniref" | head
ls -lah "$ROOT/db/checkm2" | head
ls -lah "$ROOT/db/eggnog" | head
```

eggNOG 至少要有：

- `eggnog.db`
- `eggnog_proteins.dmnd`

---

## 8. 一個完整的最短實作範例

```bash
cd EasyMetagenome
cp .env.example .env

ROOT="$HOME/easymeta"
mkdir -p \
  "$ROOT/work/seq" "$ROOT/work/result" "$ROOT/work/temp" "$ROOT/work/log" \
  "$ROOT/db/metaphlan4" "$ROOT/db/humann4/chocophlan" "$ROOT/db/humann4/uniref" \
  "$ROOT/db/checkm2" "$ROOT/db/eggnog"

# 把 .env 改成對應絕對路徑後再執行
docker compose -f docker-compose.portable.yml config

# 把你的 FASTQ 放到 $ROOT/work/seq
# 例如：Sample1_1.fq.gz, Sample1_2.fq.gz

bash docker/run-portable.sh load easymetagenome_allinone_portable.tar
bash docker/run-portable.sh run
```

---

## 9. 常見錯誤對照

1. 看不到樣本  
原因：`seq` 檔名不是 `*_1` / `*_2` 配對格式。

2. LEfSe/HUMAnN/eggNOG 被跳過  
原因：對應 DB 尚未放到 `DB_DIR`。

3. 有跑但沒有結果  
先看：`$ROOT/work/log/*.log`，再看 `result` 是否有逐步產出。

4. 權限問題 `permission denied`  
修正：

```bash
sudo chown -R "$USER:$USER" "$ROOT"
chmod -R u+rwX "$ROOT"
```

---

## 10. 可直接看的結果位置

例如你剛跑完可視化後，常在這裡看到 PDF：

- `$ROOT/work/result/metaphlan4/*.pdf`
- `$ROOT/work/result/differential/*.pdf`

---

如果你之後希望，我可以再幫你加一版「Windows 路徑範例（`D:\...`）」的 README 區塊，讓跨平台更直覺。
