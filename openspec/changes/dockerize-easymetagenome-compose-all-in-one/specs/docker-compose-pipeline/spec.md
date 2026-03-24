## ADDED Requirements

### Requirement: 一鍵啟動的 Compose 全流程執行

系統 MUST 支援使用單一指令 `docker compose up -d` 啟動完整 EasyMetagenome 分析流程，包含主流程與後續模組串接執行。

#### Scenario: 從新電腦啟動全流程

- **Given** 使用者只安裝 Docker Desktop 與 docker compose plugin，且已準備 `.env`、FASTQ 目錄與資料庫目錄
- **When** 使用者執行 `docker compose up -d`
- **Then** 系統應依序執行主流程、checkm2、humann、lefse、visualization、eggnog
- **And** 在宿主機可觀察到對應 log 與結果持續產生

### Requirement: 路徑與資源環境變數契約

所有分析腳本 MUST 支援以下環境變數作為輸入輸出與資源控制契約：`WORK_DIR`、`SEQ_DIR`、`RESULT_DIR`、`TEMP_DIR`、`DB_DIR`、`THREADS`。

#### Scenario: 使用者自訂掛載路徑

- **Given** 使用者在 `.env` 設定自訂資料夾路徑
- **When** 容器執行分析腳本
- **Then** 腳本應使用環境變數指定路徑
- **And** 不得依賴 `~/miniconda3` 或 `~/db` 等硬編碼主機路徑

### Requirement: 輸出與中間檔持久化回宿主機

系統 MUST 將 `result/`、`temp/` 與 log 檔案寫回宿主機掛載路徑，避免容器刪除後資料遺失。

#### Scenario: 容器重建後保留結果

- **Given** 一次分析流程已完成且資料輸出於掛載目錄
- **When** 使用者刪除容器並重新 `docker compose up -d`
- **Then** 既有 `result/`、`temp/`、log 檔案仍可在宿主機存取

### Requirement: 資料庫採宿主機掛載，不打包到 image

系統 MUST 透過 `DB_DIR` 掛載外部資料庫（含 metaphlan4、humann4、checkm2、eggnog），且 image MUST NOT 內含大型資料庫檔案。

#### Scenario: 共享同一套資料庫給多服務

- **Given** 宿主機已準備完整資料庫目錄
- **When** base/humann/checkm2/eggnog service 執行
- **Then** 各服務應可透過同一 `DB_DIR` 存取對應子資料庫

### Requirement: 後續模組可接續執行

系統 MUST 支援在主流程完成後接續執行 checkm2 / humann / lefse / visualization / eggnog，且可重跑單一模組而不破壞既有輸出。

#### Scenario: 重跑單一模組

- **Given** 主流程已完成且產生中間輸出
- **When** 使用者僅重跑某一模組（例如 humann）
- **Then** 系統應可利用既有輸出接續執行
- **And** 其他模組結果不應被非預期覆蓋

## MODIFIED Requirements

### Requirement: metadata 產生策略需要可控

差異分析與可視化流程 SHOULD 將 metadata 自動生成視為明確可控行為，而非無條件預設執行，以降低錯誤分組風險。

#### Scenario: metadata 不存在時

- **Given** `metadata.txt` 缺失
- **When** 使用者未啟用自動生成策略
- **Then** 系統應提示缺失並停止差異分析相關步驟
- **And** 提供可追蹤的修正指引

## REMOVED Requirements

### Requirement: 本機 Conda 必要前提

**Reason**: 容器化目標要求新電腦不需手動安裝 Conda 與分析工具。
**Migration**: 改由 Docker image 內建工具與依賴，使用 compose + volume 完成執行。
