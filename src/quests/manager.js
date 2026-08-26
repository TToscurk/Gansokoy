import { QUESTS, QUEST_BY_ID } from './data.js';

const SAVE_KEY = 'gensokyo-quests-v1';

/**
 * 手寫分支任務樹引擎。
 *
 * 引擎本身不認識任何任務內容——只認得三種邊：onTalkTo / onEnter / branch，
 * 外加兩種資料欄位：stage.scene（整場對話替換）與 start.after（鏈接啟動）。
 * 「分支」体現在 branch 邊：同一個節點依當下條件（目前是日夜）走向不同
 * 子節點，兩條分支各自有不同的 objective 文字與後續路徑，最後才收斂回同一個
 * 節點。這就是任務樹，不是單純打勾的線性清單。
 *
 * stage.scene = { npcId: [lines...] }：主線用的整場對話。跟該 NPC 說話時
 * 這組台詞「取代」原本的閒聊（不是插一句在前面）。同一場景播過一次就不再
 * 重播，重播紀錄跟任務進度一起存檔。
 *
 * start.after = 'questId'：前置任務完成的瞬間自動開啟（主線章節接龍用）。
 * start.npc 照舊：跟該 NPC 說話即開啟。quest.main = true：主線旗標。
 *
 * 狀態存 localStorage，重新整理頁面任務進度不會不見。
 */
export class QuestManager {
  constructor({ isNight }) {
    this.isNight = isNight;             // () => boolean，由 main.js 注入（讀 sky 狀態）
    this.active = new Map();            // questId -> stageId
    this.completed = new Set();
    this.scenesSeen = new Set();        // 'questId:stageId:npcId'，播過的整場對話
    this.onToast = null;                // (text, kind) => void，由 UI 層掛上去
    this.onChange = null;               // () => void，狀態改變時通知 UI 重繪任務日誌
    this._load();
  }

  _load() {
    try {
      const raw = localStorage.getItem(SAVE_KEY);
      if (!raw) return;
      const data = JSON.parse(raw);
      for (const [k, v] of Object.entries(data.active || {})) this.active.set(k, v);
      for (const id of data.completed || []) this.completed.add(id);
      for (const s of data.scenesSeen || []) this.scenesSeen.add(s);
    } catch { /* 存檔壞掉就當作新玩家，不是致命錯誤 */ }
  }

  _save() {
    try {
      localStorage.setItem(SAVE_KEY, JSON.stringify({
        active: Object.fromEntries(this.active),
        completed: [...this.completed],
        scenesSeen: [...this.scenesSeen],
      }));
    } catch { /* 無痕模式等場景 localStorage 可能整個不可寫，靜默放棄存檔即可 */ }
  }

  isActive(id) { return this.active.has(id); }
  isCompleted(id) { return this.completed.has(id); }

  /** 目前所有進行中任務的完整資訊，給任務日誌 UI 用 */
  listActive() {
    return [...this.active.entries()].map(([qid, sid]) => {
      const q = QUEST_BY_ID[qid];
      const stage = q.stages[sid];
      return { id: qid, title: q.title, objective: stage.objective, main: !!q.main };
    });
  }

  listCompleted() {
    return [...this.completed].map(qid => QUEST_BY_ID[qid].title);
  }

  /** 地圖標記用：每個進行中任務「現在該去哪」——找 NPC（npc 欄位）或進地區（region 欄位） */
  mapObjectives() {
    const out = [];
    for (const [qid, sid] of this.active) {
      const q = QUEST_BY_ID[qid];
      const next = q.stages[sid].next;
      if (next?.onTalkTo) out.push({ title: q.title, main: !!q.main, npc: next.onTalkTo });
      else if (next?.onEnter) out.push({ title: q.title, main: !!q.main, region: next.onEnter });
    }
    return out;
  }

  _toast(text, kind = 'update') {
    this.onToast?.(text, kind);
  }

  _gotoStage(questId, stageId) {
    const q = QUEST_BY_ID[questId];
    const stage = q.stages[stageId];

    // 純分支節點：next 只有 branch、沒有 onTalkTo/onEnter，代表「一到這裡
    // 就該立刻做決定」，不是在等下一次玩家互動。遞迴解掉，玩家不會感覺到
    // 中間有這個節點存在——他們只會看到任務目標直接變成分支後的內容。
    const next = stage.next;
    if (!stage.complete && next?.branch && !next.onTalkTo && !next.onEnter) {
      const dest = this._resolveBranch(next);
      if (dest) return this._gotoStage(questId, dest);
    }

    if (stage.complete) {
      this.active.delete(questId);
      this.completed.add(questId);
      this._toast(`任務完成：${q.title}`, 'done');
      this._save();
      this.onChange?.();
      // 鏈接啟動：有任務宣告 start.after === 剛完成的這個，立刻開啟。
      // 放在完成處理之後，接龍任務的「開始」toast 會壓在「完成」後面出現。
      for (const nq of QUESTS) {
        if (nq.start.after !== questId) continue;
        if (this.active.has(nq.id) || this.completed.has(nq.id)) continue;
        this._startQuest(nq);
      }
      return;
    }
    this.active.set(questId, stageId);
    this._toast(`任務更新：${q.title}`, 'update');
    this._save();
    this.onChange?.();
  }

  _startQuest(q) {
    this.active.set(q.id, 'start');
    this._toast(`${q.main ? '主線' : '任務'}開始：${q.title}`, 'start');
    this._save();
    this.onChange?.();
  }

  /** 嘗試啟動尚未開始、尚未完成、start 條件符合的任務 */
  _tryStart(npcId) {
    for (const q of QUESTS) {
      if (this.active.has(q.id) || this.completed.has(q.id)) continue;
      if (q.start.npc !== npcId) continue;
      this._startQuest(q);
    }
  }

  /** 依 branch 邊解出下一個節點 id */
  _resolveBranch(next) {
    if (next.branch === 'isNight') return this.isNight() ? next.ifTrue : next.ifFalse;
    return null;
  }

  /**
   * 對話開始時呼叫。回傳 { hint, scene }：
   *   hint  —— 插在原本閒聊之前的一句提示（沒有則 null）
   *   scene —— 整場取代閒聊的台詞陣列（stage.scene，播過不重播；沒有則 null）
   * 如果這句對話滿足了某個進行中任務的推進條件，順便推進它。
   * 注意 _tryStart 先跑：第一次跟任務 NPC 說話的「那一通」就能播 start 節點
   * 的 scene/hint，不用說第二次才進入狀況。
   */
  onTalk(npcId) {
    this._tryStart(npcId);

    let hint = null;
    let scene = null;

    for (const [questId, stageId] of [...this.active]) {
      const q = QUEST_BY_ID[questId];
      const stage = q.stages[stageId];
      const h = stage.npcHint?.[npcId];
      if (h && !hint) hint = h;

      const sc = stage.scene?.[npcId];
      if (sc && !scene) {
        const key = `${questId}:${stageId}:${npcId}`;
        if (!this.scenesSeen.has(key)) {
          scene = sc;
          this.scenesSeen.add(key);
          this._save();
        }
      }

      const next = stage.next;
      if (next?.onTalkTo === npcId) {
        const dest = next.branch ? this._resolveBranch(next) : next.goto;
        if (dest) this._gotoStage(questId, dest);
      }
    }

    return { hint, scene };
  }

  /** 玩家進入某地區時呼叫（main.js 的地區偵測邏輯已經在算這個了，順手掛勾即可） */
  onEnter(regionId) {
    for (const [questId, stageId] of [...this.active]) {
      const q = QUEST_BY_ID[questId];
      const stage = q.stages[stageId];
      const next = stage.next;
      if (next?.onEnter === regionId) {
        const dest = next.branch ? this._resolveBranch(next) : next.goto;
        if (dest) this._gotoStage(questId, dest);
      }
    }
  }
}
