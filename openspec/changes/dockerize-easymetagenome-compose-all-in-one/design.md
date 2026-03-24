## 背景

目標是讓 EasyMetagenome 在新電腦不需要手動安裝 Conda 與分析工具，並透過 `docker compose up -d` 一次啟動完整工作流。現有流程已具備模組拆分（main/checkm2/humann/lefse/visualization/eggnog），適合映射為多 image + compose service。

## 目標 / 非目標

**目標**

- 提供可重現的容器化執行方式，單指令啟動全流程。
- 透過掛載目錄保存 `result/`、`temp/`、`log` 到宿主機。
- 將腳本路徑與資源設定統一為環境變數契約。
- 保持主流程與後續模組的可串接性。

**非目標**

- 不重寫核心分析演算法與生信方法。
- 不把大型資料庫打包進 image。
- 不在本變更中擴充新的分析模組。

## 決策

### 1) 架構決策：方案 B（多 image + 多 service）

- `base`：主流程 + lefse + visualization。
- `humann`：專用 HUMAnN 執行環境。
- `checkm2`：專用 CheckM2 執行環境。
- `eggnog`：專用 eggNOG 執行環境。

原因：可避免單一巨型 image、降低重建成本、提升模組獨立維護性，且貼合既有多環境需求。

### 2) 啟動決策：保證 `docker compose up -d` 可一次啟動

- 在 `docker-compose.yml` 定義 orchestrator（例如 `pipeline-runner`）作為預設啟動 service。
- orchestrator 透過 `docker/run.sh` 以明確順序執行：
  1. `1_main_analysis.sh`
  2. `1.5_checkm2_analysis.sh`
  3. `2_humann_analysis.sh`
  4. `3_lefse_analysis.sh`
  5. `4_visualization.sh`
  6. `5_eggnog_analysis.sh`
- 其餘 service 保留可單獨重跑能力。

### 3) 路徑契約決策

- 固定契約（必需）：`WORK_DIR`、`SEQ_DIR`、`RESULT_DIR`、`TEMP_DIR`、`DB_DIR`、`THREADS`。
- `LOG_DIR` 建議加入為延伸契約，預設 `WORK_DIR/log`。
- 腳本採「環境變數優先 + 預設值 fallback」策略。

### 4) 資料庫決策

- DB 一律掛載宿主機，路徑由 `DB_DIR` 管理。
- 子目錄約定：`metaphlan4/`、`humann4/`、`checkm2/`、`eggnog/`。

### 5) 相容性決策

- 保留原有腳本入口名稱與執行順序。
- 若未提供 env 變數，維持與既有流程接近的預設行為。

## 風險 / 取捨

- 大型資料庫容量：首次準備時間與磁碟需求高。
- 記憶體需求：MEGAHIT、HUMAnN、CheckM2 可能超出 Docker Desktop 預設資源。
- 多環境維護：多 image 增加維護面，但可顯著降低耦合。
- runtime 安裝：若保留 runtime pip install 會破壞可重現性，需移入 build。
- 互動式 setup script：`read -p` 流程不適用 Docker build，需非互動化。
- metadata 自動生成：預設 Group1/Group2 可能影響差異分析可信度，需明確標註與可關閉。

## 遷移計畫

1. 新增 docker 目錄與 compose 結構。
2. 先完成六支腳本 env 參數化（不改分析邏輯）。
3. 建立四個 Dockerfile，移除 runtime 安裝依賴。
4. 建立 `.env.example` 與 `README_docker.md`。
5. 以小型測試資料驗證：FASTQ 可讀、輸出可回寫、模組可串接。
6. 對照舊流程做回歸確認，保留舊入口相容。

## 未決問題

- `docker compose up -d` 後是否以 orchestrator 完成即停止，或需常駐狀態回報 service。
- HUMAnN/eggNOG 在不同資料量下的建議資源下限（RAM/CPU）門檻值。
- metadata 自動生成是否預設關閉，並改為顯式旗標啟用。
