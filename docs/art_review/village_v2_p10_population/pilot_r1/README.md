# P10 R3b Population Pilot r1 — FINAL ART_REVIEW（等待使用者裁定）

## 範圍
16 人：MarketP10 7／Market West 5／主街一小段 4。NPC Asset Library 維持 **SEALED**；不改模型、貼圖、UV、材質、骨架、動作、import、正式 Player、市場構圖或 P9。
新 `village_v2_population_lib.gd` → `gen/population_p10.tscn` → 頂層 `Population/PopulationP10`；不放 Props，以免改變封存植被的 occupancy。每名 actor 可個別選取，不用 MultiMesh。13 Idle＋3 短 A↔B patrol；兩位婆婆 Idle、少年 Walk 1；三組双人群＋店主／買家／路人＋留白。沒有 schedule、crowd、Navigation 避讓、新角色或新動畫。

## 六類實景證據
1. `1_market_tps.jpg`：主市集正常 TPS，8.5 m。
2. `2_market_west_tps.jpg`：裏通り TPS，正常支援的 4.5 m zoom。8.5 m 入口鏡位的既有屋簷／相機問題不改 Player 或封存建築。
3. `3_main_street_tps.jpg`：主街一小段 TPS，8.5 m。
4. `4_market_high.jpg`：市集稍高視角，13 m。
5. `5_walk_through_sheet.jpg`：正式 player_yoriichi.tscn，真實 Input 移動＋collision active 六格；最新 1920×1080 重拍位移 **16.393 m**，(242.6, 1.052335, -24.5) → (242.4771, 1.144809, -40.89198)。相機保持相對方位；只修 capture helper，不改正式 Player。
6. `6_before_after.jpg`：同鏡 TPS BEFORE／AFTER，只開關人口可見性，移動與動畫 phase 固定；**兩側都保留紅衣玩家**，BEFORE 不是移除玩家的無人場景。
`population_pilot_views.jpg` 為前四類聯絡表。全部最新場景、Forward+／10:00／1920×1080；JPG 由旁邊 runtime PNG 轉出，非合成人物。`evidence/revision.json` 記來源／PNG SHA256，**不是 seal**。

## 已驗證
- Plan **11/11**、永久反向 **9/9**、scene **9/9**。
- 13 名 Idle capsule 同時檢 physics＋可見 render 三角形；3 條路線檢碰撞、步高與 stationary-NPC clearance。床面排除 ParcelLines／Wire／Footprint 與隱藏父節點，不把診斷幾何當床面。
- 30 秒 runtime：**3/3 walker 移動＋至少一次折返**，XZ ≤ 5 cm／最高接地誤差 **0.0173 m ≤ 3 cm**，末段端點正確，Idle 不動。
- 足速度少年 1.20／町人 1.41／魚販 1.32 m/s。同模型最短 13.0 m；固定 1920×1080／FOV 75／有效 projection 的審圖鏡位同模型 ≤ 2。
- Population mesh／材質 override＝原 wrapper；SpringArm 對照 4.57／4.58 m。
- 整合後 NPCLIB／MarketP10／MarketWestP10／P9 final 封存檢查通過。
- 首次獨立複查確認末段內插、逐人接地／折返、mesh／材質對照與可見床面排除正確，但抓到 PNG 實際 1920×1061。只修 review capture 的 borderless 視窗與實際尺寸檢查後，已重拍 **14/14 張 1920×1080**，所有 PNG chunk CRC 通過；source 7 檔中只有拍攝腳本變動，actor／generator／gate／views／兩個 scene 雜湊未變。新 scene 9/9 與 NPCLIB 548 檔 --seal 已再執行通過。第二次複查確認尺寸／CRC／雜湊一致，但抓到最後一張失敗可能被結尾 quit() 覆寫成 exit 0；現改為 snap 回傳錯誤碼、所有 caller 失敗立即退出 run，並實機測試 last-size／last-save／after-save／before-save **4/4**（退出碼 2／3／3／3），正向全拍 exit 0。最終獨立收尾已取得 **CAPTURE_EVIDENCE_CLOSURE_PASS**（`deleg_36c32f4d`），詳見 `evidence/independent_check_final.md`；此 PASS 不代替 ART_APPROVED，也不消除下方 P5／P8 失敗。
上述**不是逐一動畫手掌／衣物頂點對全部道具的穿模認證**。

## 完整回歸：96 群組，94 通過／2 失敗
全套輸出與最後 footer 已齊，**不是全綠，也不宣稱正常 exit 0**。詳見 `evidence/full_regression_summary.json` 與 `full_regression_final.log`。
- **P5 白名單 scope debt**：398 個違規；本輪不擴白名單、不重開 P5。
- **P8 GPU budget**：原完整回歸的量測受到外部 GPU 負載污染。隻狼關閉後、只在記憶體移除 Population 並沿用封存 benchmark 的暫測為 T1 +6.09 ms／High +4.09 ms；GPU preflight 波動不合格，維持 **PRELIMINARY**，不是 strict PASS，也不能判為已確認 regression。
POP 與 NPCLIB／MKT／MW／P9F 在完整回歸通過；拍攝工具修正後僅重跑受影響的 capture／scene／NPCLIB seal，不把原全套結果偽稱新一輪測試。
舊 `revision_pre_viewport_fix.json` 只保留歷史宣告與雜湊，不代表目前原圖；最新 `revision.json` 逐張驗尺寸／CRC／SHA256。

## 視覺界線
同鏡比較確實多了居民；但三區仍偏冷清，Idle／Walk 缺少買賣、聊天、搬運動作，較像「已有店主與零散買家」，**不能宣稱已充分呈現有人生活交易的村落**。棚架／燈籠的自然遮擋保留。Technical PASS 不是 ART_APPROVED；只送 Pilot 審圖，未批准不擴全村。

