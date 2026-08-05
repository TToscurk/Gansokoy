# 美術風格筆記 —— 森林／幻想鄉場景的市場觀察與本專案的定位

（2026-08，香霖堂卡通化打樣時整理。參考基準：使用者提供的兩張畫面 ——
hordes.io 的森林小鎮、Godot「MAKE YOUR FIRST 3D RPG」教學的草原。）

## 市面上的四大主流風格

**1. 吉卜力／手繪水彩系（目前聲量最大）**
大色塊、低對比陰影、暖色陽光斑；樹冠是「分層的雲朵」而不是一片葉子。
草地是這個風格的招牌：滿地帶漸層的草卡（根暗尖亮），風吹時整片搖。
Blender Geometry Nodes 做吉卜力草是近年教學圈的顯學
（[80.lv 的手繪草文章](https://80.lv/articles/beautiful-hand-drawn-grass-created-in-blender)、
[Geometry Nodes 吉卜力草](https://80.lv/articles/fascinating-ghibli-style-grass-setup-crafted-with-geometry-nodes)）。
代表：《薩爾達 曠野之息》《原神》草地、大量獨立遊戲。

**2. 低多邊形復興（low-poly renaissance）**
2025 的 low-poly 不再是「省錢」的代名詞，而是刻意的風格：平塗色、
幾何陰影、乾淨剪影，配上現代光照（AO、bloom）。
產業趨勢文（[ThinkGamerz 2025 風格榜](https://www.thinkgamerz.com/best-game-art-styles-2025/)、
[Kevuru 的年度整理](https://kevurugames.com/blog/what-is-game-art-in-2025-types-trends-features/)）
都把它列為主流之一。hordes.io 就在這一系 —— 方塊感角色 + 手繪貼圖地面。

**3. 手繪貼圖／魔獸系（hand-painted）**
幾何簡單但貼圖畫滿細節（石板路的每塊磚都是畫的）。hordes.io 的地面
與建築牆面是這種。成本在「會畫貼圖的人」，程式生成難以替代。

**4. 寫實／半寫實（photoreal PBR）**
照片掃描材質 + Nanite/Lumen。跟東方二次創作的氣質不合，跳過。
（Gensokoy3D 舊專案的 Poly Haven 雙軌制其實就是往這走過一步 ——
結論是質感有了、但「幻想鄉味」反而淡了。）

## 兩張參考畫面拆解

- **hordes.io**：主體是 2 + 3 的混合 —— 低多邊形建築 + 手繪貼圖 + 濃霧藍
  色調。氛圍極好，但手繪貼圖量大，個人專案難以複製。
- **Godot 教學（Rikikiz）**：主體是 1 + 2 —— 平塗低多邊形樹（堆疊錐的杉樹）
  + 高密度漸層草。**這條最容易做到、效果又立竿見影**：
  草的密度與漸層佔了畫面好感度的一半以上。

## 本專案的定位（香霖堂打樣採用）

**「低多邊形 × 吉卜力分層」混合**，理由：

1. 全程式生成可以做到（不依賴會畫貼圖的人）；Blender headless 腳本
   （`godot/assets/blender/make_trees.py`）產樹，頂點色烤層次。
2. 幻想鄉的氣質是「柔和的鄉野」——吉卜力的暖色草地比 hordes.io 的
   冷霧更貼題；但保留 low-poly 的乾淨剪影，避開手繪貼圖的人力坑。
3. 具體配方：
   - 樹冠分 3~4 層，每層一個色階（下暗上亮），flat shading
   - 草：根 `(0.16,0.30,0.10)` → 尖 `(0.55,0.74,0.30)` 的漸層簇，密度優先
   - 地面：飽和綠底 + 黃綠陽光斑 + 暖沙色小徑（烤成低頻貼圖）
   - 薄霧 + 暖陽光；森林深處色調壓暗做縱深
4. 之後的手工資產（Blender 建模的店屋、角色）疊在這個基底上，
   風格語彙一致：大色塊、清楚剪影、少貼圖多頂點色。

## 下一步

- 風吹草動：Godot shader 對草 MultiMesh 加頂點搖擺（教學畫面的靈魂）
- 角色改造時沿用同一語彙（cel 色階 + 乾淨剪影），參考 VRM 東方模型
- 其他 7 張圖重做時直接沿用 toon_flat 材質與樹種資產
