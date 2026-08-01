---
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, TaskCreate, TaskUpdate, mcp__chrome-devtools__navigate_page, mcp__chrome-devtools__list_console_messages, mcp__chrome-devtools__take_screenshot
description: 自動抓現有地圖的錯誤修掉，然後照 mapRegistry.js 繼續蓋下一張未完成的圖
argument-hint: [地圖id，選填]
---

## 前提

這個指令需要 chrome-devtools MCP。如果 `mcp__chrome-devtools__navigate_page`
或 `list_console_messages` 不存在，**先告訴我就停下**，不要自己降級成
「靜態檢查猜測」然後當作驗證通過。

> MCP 工具是**開 session 時**載入的。剛用 `claude mcp add` 裝完的話，
> 要重開 session 才會出現。

## 第一步：全面語法檢查（不靠瀏覽器）

對 `main.js`、`maps/**/*.js`、`src/**/*.js` 跑語法檢查。

**注意**：本專案 package.json 是 `"type": "commonjs"`，但所有 `.js` 都是
ES module。直接 `node --check <檔案>` 會把 51 個檔案**全部誤判成語法錯誤**
（`Cannot use import statement outside a module`）。一定要走 stdin + 指定型別：

```bash
for f in main.js $(find src maps -name '*.js'); do
  node --check --input-type=module < "$f" 2>&1 | sed "s|^\[stdin\]|$f|" \
    || echo "SYNTAX FAIL: $f"
done
```

（`--input-type=module` 只能吃 stdin，所以錯誤訊息裡的檔名是 `[stdin]`，
上面的 `sed` 把它換回真檔名。）

有語法錯誤先列出「檔名:行號 錯誤內容」清單，全部修完才能進下一步。

## 第二步：實際開起來檢查（chrome-devtools MCP）

1. 先確認 port 沒被佔用，再用 run_in_background 起 dev server：
   ```bash
   curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:5603/ \
     || node tools/dev-server.mjs . 5603
   ```
2. 依序對 `index.html` 與每個 `maps/*/index.html`：
   - `navigate_page` 開頁面
   - `list_console_messages` 讀 console。**error 等級一律要處理**
     （warning 記錄即可，不擋下一步）。mapRegistry.js 的連線對稱自檢
     如果噴錯，這裡就會看到，一併修掉。
   - `take_screenshot` 存一張，看構圖有沒有明顯不對：地形穿模、角色卡進
     地形、傳送點沒發光、天空/霧色套錯地區、**路面互相閃爍**。
3. 抓到的錯誤照訊息裡的檔名行號直接修。修完**只針對同一張圖**重跑
   `navigate_page` + `list_console_messages` 驗證乾淨即可，不用整輪重跑。

> 神社（`index.html`）要先點掉角色選擇畫面才會有 `ctrl`；
> 用 `#veil` 這個元素當點擊目標。

## 第 2.5 步：角落抽查

第二步的截圖只拍了預設視角（出生點），容易漏掉樹卡建築、地形穿模這種
局部問題 —— 出生點附近本來就是最被照顧到的地方。每張圖額外做這件事：

1. 用 `evaluate_script` 在頁面裡直接把玩家瞬移到**地圖四個角落**，以及
   **scatter 密度最高的區域**（樹叢／建築群聚處），每個點 `take_screenshot`
   存一張。座標從各圖的 debug handle 拿（`window.__<mapid>`，playSize
   的四角往內縮 10~15 公尺，避開邊界圍坡）：

   ```js
   // 瞬移 → 讓控制器落地 → 渲染一格，缺一不可
   __bamboo.tp(x, z);        // 有些圖的簽名是 tp(x, y, z)，先看 handle
   __bamboo.step(30);        // 跑幾格讓重力把角色貼回地面、LOD 換好
   __bamboo.frame();         // 手動渲染，不然截到的是瞬移前那一幀
   ```

   密集點怎麼找：竹林看 `叢生擋人處`、里看主街與稗田邸、花田看花海中心、
   獸道看三岔口。拿不準就取 `PATHS.samples` 中段附近的路旁。

2. 看這幾張截圖，抓明顯的**穿模／卡在地形裡／裝飾物疊在建築上**：
   角色半身沒入地面、樹幹從屋頂長出來、草叢蓋住路面、遠景剪影跑進可走範圍。

3. **這一步是輔助抽查，不是全圖走位測試。** 抓不到問題不代表沒問題。
   回報時老實寫「已抽查四角與密集區，但沒有走遍全圖」，
   **不要**講成「已驗證整張圖沒有穿模問題」。

## 第三步：只有第一、二步全部乾淨，才做這步

讀 `src/world/mapRegistry.js` 的 `MAP_INFO`，找出第一個 `built: false` 的圖
（若我有給 `$ARGUMENTS`，優先做參數指定的那張，忽略 built 狀態）。

該圖的 `mobTheme`、`playSize`、`connections` 都已定好，**照著蓋**，不要另外
發明怪物主題或改尺寸。蓋的過程若發現預設值不合理，先蓋出能動的版本，
再跟我提你想改什麼，不要默默改掉。

### 照現有寫法做（不要另創）

**參考對象是實際的圖**：`maps/trail/`、`village/`、`bamboo/`、`eientei/`、
`namelessHill/`、`sunflower/`。README 的「地圖與串接」段落只用來看整體
架構，**細節一律以程式碼為準**（那一段可能落後於實作）。

- 路徑用 `PathNet` + `ribbonOnGrid`，不寫死高度公式
- 地形二次式**一定要封頂**（`Math.min`）—— 不封的話網格邊緣會衝到
  一百公尺高，遠看是兩道白色巨牆
- 重複物件用 `InstancedMesh`，大圖比照 bamboo 做**空間格切**
  （單一個 InstancedMesh 的包圍盒涵蓋整張圖，視錐裁剪永遠命中）
- 撒點沿 `PATHS.samples` 撒，不要整張圖亂撒再篩（大圖命中率不到一成）
- 隨機佈局用**決定性亂數**（比照 bamboo 的 LCG），每次重整要長一樣
- 地形/裝飾共用 `flora.js`、`groundmesh.js`
- 新怪物基於 `mobcore`，只寫自己的 `update` 行為，檔名份量比照 `rabbits.js`
- 世界建完呼叫 **`mergeStaticByMaterial(world, { cell: 40~60 })`**
  —— 依圖大小選 cell。**不要用 `(world, ['portal'])`**，那是舊簽名，
  傳陣列會被當成 skipNames、cell 吃預設值 60 等於沒分格；
  portal 現在靠 `userData.noMerge` 自己跳過，不需要 skipNames。

### 每張圖都有的慣例（漏了就是 bug）

1. **`?from=` 出生點分流** —— 依來向決定出生在哪個出入口並轉好朝向。
2. **多段路的 `lift` 要各差 1.2 公分**
   （`ribbonOnGrid(..., 0.05 + i * 0.012)`）。支徑都從主徑岔出，重疊處
   兩層路面同高 = 深度緩衝分不出前後 = 整片閃爍。`GroundGrid` 只治
   「路 vs 地面」，治不了「路 vs 路」。
3. **草叢離路緣留 1.2 公尺**（`pathDist(x,z) < 1.2` 就不種）。
   一叢草放大後半徑約 0.5 公尺，留太少葉尖會蓋到路面上。
4. **有 NPC 的圖**：`index.html` 要內嵌 `#talk` 那組 DOM
   （`src/ui/dialogue.js` 依賴它），樣式抄 `maps/eientei/index.html`。
5. **有 hazard 的圖**：毒區跟「哪裡不長那種植物」要用**同一個述詞**
   （`addCircle(..., { safe })`），否則會出現「看不到花卻在掉血」。
6. **`ctrl.maxGrade`** —— 邊界圍坡要爬不上去（既有圖用 0.95~1.05）。
   神社那種瞬間高度差的石階不能設，會變成牆。
7. **debug handle**：`window.__<mapid>`，比照現有圖曝露
   `ctrl / heightAt / tp / step / frame / setHour / setTimeFlowing` 與各出入口常數
   （測試腳本靠這個開）。

### 一定要接上另一端

新圖蓋完**不會自己接上世界**。`connections` 是雙向的，另一端那張圖
必須也開出口，否則遊戲裡走不到 —— 就是一座孤島。

例：`village.connections` 已經列了 `kourindou`，但 `village.js` 目前
**只有回獸道一個出口**，沒有西南門。蓋 kourindou 就得同時在 village 加：
出口光點（`makePortalGlow`）、`nearXXX()` 判定、`E` 的 `location.href`、
HUD 提示，以及目的地方向的**遠景**（讓玩家在傳送點就看得到下一張圖的樣子
—— 這是既有六張圖都有的做法）。

## 完成後

1. 回到第一、二步，驗證新圖乾淨（語法通過 ＋ console 無 error）。
2. **走一次實際路線**確認接得上：從既有圖走到新圖再走回來，兩邊出生點都對。
3. 全部通過才改 `mapRegistry.js`：`built: false` → `built: true`，
   **並補上 `entry: 'maps/<id>/'`**（已建的六張都有這欄，未建的都沒有）。
   這是唯一的進度紀錄，不要另外維護清單檔案。
4. 用一句話報告：做了什麼、有沒有偏離 MAP_INFO 預設值、有沒有規格沒寫清楚
   要自己判斷的地方。
5. **一次只做一張圖就停**，不要連續做兩張。
6. 不要主動問我停下 —— 除非是「兩種寫法都合理但會動到已經蓋好的圖」
   這種真的需要我決定的事，其他一律照 MAP_INFO 跟現有寫法自己判斷後繼續。
