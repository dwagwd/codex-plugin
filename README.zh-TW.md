# Codex Usage Widget

原生 macOS 桌面用量小卡，顯示方案額度、Codex 帳號 token 速度與重置倒數。使用 AppKit／Swift，不需要瀏覽器執行環境，不透過模型對話輪詢。

[English](README.md) · [MIT 授權](LICENSE) · [隱私](PRIVACY.md) · [其他 agent 連接指南](docs/providers.md)

非官方社群專案，與 OpenAI、Anthropic、Google、Cursor 無隸屬或背書關係。

## 功能

- 主卡 260 × 128 pt；收合為 182 × 32 pt。支援拖曳、記住位置、置頂、選單列與齒輪設定。
- 可以只顯示一個額度，或勾選最多四個額外額度一起顯示；卡片隨選擇增高，各來源分開計算。
- `%/時` 是額度「百分點／小時」的簡寫：一小時由 20% 至 25%，顯示 5%/時，不是相對成長率 25%。
- 觀測期間可設 1 分鐘至 30 天；數值以分鐘／小時／天輸入，速度顯示單位獨立設定。
- 繁中、簡中、英文、日文、韓文、西班牙文、法文、德文、巴西葡萄牙文、義大利文與跟隨系統。歡迎母語使用者協助校對。
- 文字與背景 RGB 三原色自訂（0–255），或使用系統外觀。
- 省電模式：每 120 秒讀取 Codex，每 15 秒更新畫面；一般模式為 60 秒／1 秒。隱藏時停止畫面計時，有新資料才重算速度。
- Claude Code 與 Antigravity CLI 官方 status-line 橋接。Cursor Teams 支援額外付費支出上限，並非個人方案額度。接入前請看[連接指南](docs/providers.md)。

## 建置與安裝

需要 macOS 13+、Swift 5.9+／Xcode Command Line Tools、測試用 Python 3，以及已登入 ChatGPT 帳號的 Codex App 或 CLI。Codex 核心小卡不依賴 Python，其他 agent 橋接需要 Python 3。

```sh
./scripts/check.sh
./scripts/build-install.sh
./scripts/launch.sh
```

安裝於 `~/Applications/Codex Usage Widget.app`。重複啟動只顯示原本的小卡；不設定登入自動啟動。齒輪可調整偏好設定；點標題切换主額度，拖曳空白處移動。滑鼠停在速度上可查看實際觀測長度與定義。

## 數據定義

Codex 額度來自 `account/rateLimits/read`，tokens 來自 `account/usage/read` 的帳號累積回報。兩者獨立計算，不能用固定倍率互換。共享額度無法拆成各模型消耗；Spark 等獨立窗口則分開顯示。Token 回報可能延遲，速度 0 代表未回報增加。

預設觀測最近一小時。暖機需 5 分鐘或所選較短期間；不足完整期間顯示估算。重置、用量下降、帳號或方案切換、時鐘倒退、超過五分鐘中斷均重設基準。Codex 取樣時保留最近最多 31 天；停止時既有檔案會留到下次取樣或手動移除。多日估算需要連續觀測。Bridge 的速度歷史目前保存在記憶體，重開小卡會重新累積。

倒數歸零只表示等待來源確認；缺少資料顯示「—」。Claude／Antigravity 需要 CLI 回報，靜置或退出超過五分鐘會標記過期。其他 agent 的 context window 不被當成累積 token 消耗量。

## 開源準備

採 MIT。包含貢獻、安全回報、隱私、變更記錄、CI、手動打包 workflow 與來源匯出檢查。目前 GitHub 維持私人，不自動建立公開 release。App 為本機 ad-hoc 簽章，尚未公證。

```sh
./scripts/package.sh
```

產出與建置快取預設在 `~/Library/Caches/CodexUsageWidget/`。發布步驟見 [releasing.md](docs/releasing.md)，測試範圍見 [validation.md](docs/validation.md)。

本機採樣在 `~/Library/Application Support/CodexUsageWidget/`，偏好設定屬於 `local.codex.usage-widget`。請勿將這些個人資料推送至 GitHub。移除時先退出 App；如有安裝其他 agent 橋接，依連接指南還原 statusLine 設定，再移除 App、資料及插件。
