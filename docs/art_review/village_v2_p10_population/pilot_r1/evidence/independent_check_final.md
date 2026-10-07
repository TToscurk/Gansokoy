# P10 R3b Population Pilot — 最終 independent check

## 結論
**CAPTURE_EVIDENCE_CLOSURE_PASS**，來源：唯讀獨立複查 `deleg_36c32f4d`。
此結論是 capture 技術證據收尾，不是 ART_APPROVED，也不代表完整回歸全綠。

## 已關閉的問題
- 先前 PNG 實際 1920×1061，與 gate 宣告不符：review-only borderless 視窗鎖定實際 1920×1080，每張存檔前檢查 Window／Image 尺寸與 projection；重新渲染，不裁切／放大舊圖。
- 先前 snap 失敗呼叫 quit(2/3)，caller 仍可能落到最末 quit() 覆寫 exit 0：snap 現回傳 2／3／OK；walk／after／before 三個 caller 全部 await 結果，失敗即 quit(error) 並 return，walk 亦釋放輸入／停止 physics／釋放 helper。
- 程式依據：`godot/tools/shot_village_v2_population.gd:20–32,91–100,107–123`。

## 獨立核驗與實機證據
- 最終 14 張 runtime PNG 全為 **1920×1080**，**4005 個 chunk CRC 全通過**。
- **7 source、14 PNG、16 logs、注入腳本與失敗測試 manifest SHA** 全相符。
- 四個真渲染故障注入：last-size／last-save／after-save／before-save，退出碼 **2／3／3／3**；成功張數 **13／13／0／1**，無失敗目標 PNG，無成功 POPWALK footer。測試透過真 filesystem 阻塞或 viewport 改尺寸，再呼叫 production super.snap；不是合成回傳。
- 正向全拍 exit **0**，14 次成功拍攝；正式 Player 真 Input 實走 **16.3926963806152 m**。
- Scene **9/9**，三 walker 在 30 秒內移動＋折返，最高接地誤差 **0.0173 m**。
- Population 維持三區 **7／5／4＝16 人**、13 Idle＋3 patrol。
- NPCLIB **548 檔 SHA 零不符、零封存外新增**。相對 full-suite source 僅 capture 工具 source 改動，其餘六個 actor／generator／gate／views／scene source 不變。
- 失敗測試 manifest SHA256：`8dc4293dcdf6b4e9f73d01ab23d1ddd0efa773ca8108be9008516ce04fcb2473`。

## 仍保留的完整回歸結果
**96 群組／94 通過／2 失敗**，原始 log 與 footer 已保存；不宣稱正常 exit 0。
- P5 白名單 scope debt：398 個違規，本輪不擴白名單、不重開 P5。
- P8 GPU budget：原始量測受外部 GPU 負載污染。隻狼關閉後 baseline T1 +6.09 ms／High +4.09 ms，但 GPU preflight 波動未合格，只能記 **PRELIMINARY**，不是 strict PASS，也不是已確認 regression。

## 美術與下一包界線
目前僅提交 **P10 R3b Population Pilot — FINAL ART_REVIEW**，未 ART_APPROVED、未封存人口、不擴全村。
只有使用者授予 R3b ART_APPROVED 後，才進 R3c Mixamo Activity Pack；Activity Pack 通過後才可 Village Core Population Expansion。NPC Asset Library 繼續 SEALED。
