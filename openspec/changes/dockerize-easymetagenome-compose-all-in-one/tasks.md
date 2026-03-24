## 1. OpenSpec 與契約定義

- [x] 1.1 整理並確認 proposal/design/specs 內容與範圍一致，特別是「方案 B + 一鍵 up -d」行為。 (impact: docs, schema)
- [x] 1.2 定義環境變數契約與預設值策略（`WORK_DIR`、`SEQ_DIR`、`RESULT_DIR`、`TEMP_DIR`、`DB_DIR`、`THREADS`，以及建議 `LOG_DIR`）。 (impact: schema, compatibility)

## 2. 腳本參數化改造

- [x] 2.1 修改 `1_main_analysis.sh` 以 env 優先取代硬編碼路徑，並保持既有流程邏輯。 (impact: module, compatibility)
- [x] 2.2 修改 `1.5_checkm2_analysis.sh`、`2_humann_analysis.sh`、`3_lefse_analysis.sh`、`4_visualization.sh`、`5_eggnog_analysis.sh`，統一路徑與執行緒參數模式。 (impact: module, compatibility)
- [x] 2.3 將 runtime pip install 與互動式 setup 依賴從執行流程中移除，改由建置階段處理。 (impact: module, compatibility)

## 3. Docker 映像與 Compose 編排

- [x] 3.1 建立 `docker/base.Dockerfile`、`docker/humann.Dockerfile`、`docker/checkm2.Dockerfile`、`docker/eggnog.Dockerfile`。 (impact: module)
- [x] 3.2 建立 `docker-compose.yml`，包含多 service、共用 volume、`pipeline-runner` 一鍵啟動流程。 (impact: module, schema)
- [x] 3.3 建立 `docker/run.sh` 以固定順序串接六支腳本，並提供單模組重跑參數。 (impact: module, compatibility)

## 4. 使用者配置與文件

- [x] 4.1 建立 `.env.example`，涵蓋掛載路徑、執行緒、資源建議與資料庫目錄規約。 (impact: docs, schema)
- [x] 4.2 建立 `README_docker.md`，說明最小安裝需求、`docker compose up -d` 啟動方式、常見錯誤排查。 (impact: docs)

## 5. 驗收與回歸

- [x] 5.1 驗證可從掛載目錄讀取 `*_1.fastq` / `*_2.fastq`，並持續回寫 `result/`、`temp/`、log。 (impact: module, compatibility)
- [x] 5.2 驗證主流程後可接續執行 checkm2 / humann / lefse / visualization / eggnog。 (impact: module)
- [x] 5.3 驗證新電腦無需手動安裝 Conda 與工具，僅需 Docker Desktop + compose plugin。 (impact: compatibility, docs)
- [x] 5.4 進行風險檢查：大型 DB 容量、記憶體需求、多環境維護、metadata 分組風險。 (impact: docs, compatibility)
