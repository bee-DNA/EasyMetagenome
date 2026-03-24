## 為什麼

EasyMetagenome 目前流程依賴本機 Conda、多個環境與硬編碼路徑（例如 `~/miniconda3`、`~/db`），在新電腦重建成本高、啟動不一致，也不利於團隊交接。使用者目標是以 `docker compose up -d` 一條指令啟動整套分析，並可透過掛載目錄保留輸出與 log。

本變更要把現有 shell pipeline 包裝成可攜、可重現的 Docker Compose 工作流，確保新機器僅需 Docker Desktop + compose plugin 即可執行。

## 變更內容

- 採用方案 B：多 image、多 service 的 Compose 架構。
- 新增容器化產出物與啟動入口：
  - `docker/base.Dockerfile`
  - `docker/humann.Dockerfile`
  - `docker/checkm2.Dockerfile`
  - `docker/eggnog.Dockerfile`
  - `docker-compose.yml`
  - `docker/run.sh`
  - `.env.example`
  - `README_docker.md`
- 將現有六支 pipeline 腳本改為環境變數驅動，至少支援：
  - `WORK_DIR`
  - `SEQ_DIR`
  - `RESULT_DIR`
  - `TEMP_DIR`
  - `DB_DIR`
  - `THREADS`
- 移除對固定 Conda 路徑與 runtime pip install 的流程假設。
- 將大型資料庫改為宿主機 volume 掛載，不打包進 image。

### 新能力

- `docker-compose-pipeline`: 一條 `docker compose up -d` 啟動可執行全流程的容器化分析。

### 變更能力

- `main-analysis-runtime`: 由腳本相對路徑與 Conda 假設，改為可參數化、容器內可直接執行。
- `module-chaining`: 主流程完成後可延續執行 checkm2 / humann / lefse / visualization / eggnog，且輸出持久化回宿主機。

## 影響

- 受影響模組：六支分析腳本、環境建置方式、啟動說明文件。
- 版本影響：
  - project version：會有使用方式變更（新增 Docker 入口）。
  - pipeline schema version：新增可配置執行契約（路徑與資源參數）。
- 相容性影響：保留舊 shell 入口但改為支援 env 覆寫，降低既有使用者遷移成本。
- 遷移路徑：
  1. 先準備宿主機資料與 DB 目錄。
  2. 由 `.env` 設定掛載路徑與執行緒。
  3. 使用 `docker compose up -d` 啟動全流程。
  4. 依需求分別重跑單一模組。
