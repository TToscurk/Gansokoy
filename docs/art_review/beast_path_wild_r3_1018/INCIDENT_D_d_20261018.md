# 事件記錄：D:\d 資料夾誤建＋誤刪（2026-10-18）

## 經過（依 Hermes 工具紀錄 state.db，session 20261018_003836_96fd20）
| 時間 | 動作 |
|---|---|
| 13:17:42 | 我在 git-bash 設 `D=/d/神社/shrine/docs/art_review/beast_path_wild_r2_1018`，交給 **Windows 版 python**（`compare_sheet.py`）當輸出路徑。Windows python 把 `/d/…` 解讀成「目前磁碟根目錄\d\…」→ `os.makedirs` 建出 `D:\d\神社\shrine\docs\art_review\beast_path_wild_r2_1018\`，寫入 3 張 jpg。 |
| 13:19:39 | 發現位置錯，`ls` 該子資料夾＝只有那 3 張 jpg → `mv` 到正確位置 → **`rm -rf "D:/d"`（整個資料夾，沒先列出 D:\d 頂層內容）**。 |

## 調查：D:\d 在 13:17 之前是否已存在？
- **D:\ 根目錄的歷史列表**（工具輸出中共 17 次完整列出 D:\）：09-10、09-16、09-24、09-27、09-28、10-01、10-03、10-04、10-05、**10-09 03:26（最後一次）**——**都沒有 `d`**。13:19 刪除後的列表也沒有。
- **10-09 03:26 → 10-18 13:17 之間所有 Hermes session 的工具呼叫**（777 筆含 `/d/` 的呼叫逐筆掃描）：沒有任何一筆用原生程式（Windows python／Godot／Blender）**寫入** `/d/…` 形式的路徑；
  - 10-05 00:13 有一次同樣的路徑錯誤（`uv run python sheet_r53.py … /d/神社/…`），結果是 `FileNotFoundError`——PIL 不會建資料夾，**沒有建出 D:\d**，也證明當時 `D:\d\神社\…` 不存在。
  - 10-14 的 Blender 量測腳本讀 `SAMPLES=/d/參考圖概念圖/…`（唯讀）＝讀不到、無輸出，沒有寫入。
  - 10-17 的 `S=/d/參考圖概念圖/…/v24_arm078` 只用在 bash `cp`（git-bash 會正確轉成 D:\參考圖概念圖），python 端用的是 `r"D:\參考圖概念圖…"`。
- Windows「最近使用」捷徑（%APPDATA%\Microsoft\Windows\Recent）沒有任何指向 `D:\d` 的項目。
- **無法查的部分**：NTFS 變更日誌（USN journal）需要系統管理員權限（`fsutil usn readjournal` 回「存取被拒」）；Hermes 以外的程式（你自己的操作）在 10-09 之後有沒有建過 D:\d，我看不到。

## 結論
- 依現有紀錄，**D:\d 最有可能是我 13:17 那次呼叫才建出來的**，刪掉的內容就是那 3 張 jpg（已搬到 `docs/art_review/beast_path_wild_r2_1018/`，完好）。
- 但我**沒有在刪除前列出 D:\d 頂層**，所以無法 100 % 排除「10-09 之後你自己建過 D:\d」的可能。若要確認，可在**系統管理員 PowerShell** 執行（只讀、不改任何東西；日誌若已輪替掉就查不到）：
  `fsutil usn readjournal D: csv | Select-String -SimpleMatch '"d"'`
  若在 10-18 13:17 之前就有名為 `d` 的「File create」紀錄＝原本就存在。

## 之後的規則（已寫進 skill beast-path-zone-rework）
- 原生程式（Windows python／Godot／Blender）的路徑一律用 `D:/…` 或 `C:/…`，不用 `/d/…`。
- 不刪除任何未確認來源的資料夾；只動自己這一輪建的、且有列出內容確認過的檔案。
