// 日之呼吸的技能系統 —— 主動技、被動技、小技能。
//
// 十三型（forms.js）本來就是連段的骨幹：點左鍵依序輪過去。這裡加的是
// 另一層 —— 幾個「指定使出、有冷卻、威力另計」的招，加上一整組不用按鍵、
// 隨等級開通的被動。
//
// 設計原則：
//   1. 主動技不另外做動畫。它指定十三型裡的某一型，走 Combat.useForm()
//      同一條執行路徑 —— 手感與刀光才不會跟普通攻擊分岔，也不用維護兩套。
//      技能與普通攻擊的差別在倍率、冷卻、以及該型平常在連段裡輪不太到。
//   2. 被動全部收斂成一個 dmgMul() 回傳值，由 Combat 每一擊問一次。
//      同一刀砍中的每一隻吃到的倍率因此一致 —— 不然一群怪裡會有幾隻
//      莫名其妙特別痛。
//   3. 解鎖綁角色等級（progression.js 的 charLv），不另外做技能點。
//      這是割草遊戲，砍就會變強，不該再叫玩家開面板配點。
//
// 設定考據（鬼滅之刃）：緣一是史上唯一的「天生擁有斑紋與透き通る世界」
// 的劍士。斑紋是瀕死時覺醒的紋樣、透き通る世界能看穿對手體內的動向、
// 全集中常中是把呼吸維持在戰鬥狀態的基本功。這裡把它們做成被動與增益。

import { FORMS } from './forms.js';

/* ────────────────────────────────────────────────── 主動技 ── */
/**
 * form   指向 forms.js 的索引（技能不另外做動畫，見檔頭）
 * dmgMul 這一招的傷害倍率
 * cd     冷卻（秒）
 * unlock 解鎖所需的角色等級
 * buff   非攻擊型技能的增益（見 SkillSystem._applyBuff）
 */
export const SKILLS = [
  {
    id: 'kasha', key: 'Digit1', slot: '1',
    zh: '伍之型・火車', en: 'KASHA',
    form: 4, dmgMul: 1.9, cd: 8, unlock: 1,
    desc: '一記帶著火輪的重斬。範圍不大但很痛，開場破陣用。',
  },
  {
    id: 'dragon', key: 'Digit2', slot: '2',
    zh: '拾壹之型・日暈之龍・頭舞', en: 'DRAGON',
    form: 10, dmgMul: 2.2, cd: 15, unlock: 3,
    desc: '化龍前突，貫穿一整條線上的敵人。',
  },
  {
    id: 'rinne', key: 'Digit3', slot: '3',
    zh: '拾參之型・輪迴', en: 'RINNE',
    form: 12, dmgMul: 2.6, cd: 24, unlock: 6,
    desc: '十三型的收招。全周最大範圍，被圍住時的解圍技。',
  },
  {
    id: 'clear', key: 'Digit4', slot: '4',
    zh: '透き通る世界', en: 'CLEAR WORLD',
    cd: 42, unlock: 9,
    buff: { dur: 8, dmgMul: 1.6, alwaysCrit: true },
    desc: '看穿對手體內的動向。八秒內每一擊都命中要害。',
  },
];

/* ────────────────────────────────────────────────── 被動技 ── */
// 沒有按鍵，達到等級自動生效。小技能（拔刀術、常中）也收在這裡 ——
// 它們的本質一樣是「不用按、一直在」的東西，分成兩份表只會多一套邏輯。
export const PASSIVES = [
  {
    id: 'battou', zh: '拔刀術', en: 'BATTOUJUTSU', unlock: 1, minor: true,
    desc: '納刀狀態下的第一刀，傷害 +50%。',
  },
  {
    id: 'muga', zh: '無我之境', en: 'MUGA', unlock: 2,
    desc: '五秒沒有受傷時，下一擊必定命中要害（2 倍傷害）。',
  },
  {
    id: 'joutyuu', zh: '全集中・常中', en: 'TOTAL CONCENTRATION', unlock: 4, minor: true,
    desc: '最大血量 +30，脫離戰鬥後的回血速度加倍。',
  },
  {
    id: 'mark', zh: '斑紋', en: 'DEMON SLAYER MARK', unlock: 5,
    desc: '血量低於四成時覺醒：傷害 +35%、移動速度 +15%。',
  },
  {
    id: 'clarity', zh: '透世之器', en: 'SEE-THROUGH', unlock: 8,
    desc: '每一擊有 18% 機率看穿要害，造成 2 倍傷害。',
  },
];

const CRIT_MUL = 2.0;
const MUGA_DELAY = 5;          // 幾秒沒受傷觸發無我之境
const MARK_THRESHOLD = 0.4;    // 血量比例低於這裡斑紋覺醒

export class SkillSystem {
  /**
   * @param {object} deps
   * @param {import('./combat.js').Combat} deps.combat
   * @param {import('../player/vitals.js').Vitals} deps.vitals
   * @param {import('../player/progression.js').Progression} deps.prog
   * @param {object} deps.ctrl   PlayerController（斑紋要改移動速度）
   * @param {object} [deps.ui]   { skills(list), banner(text), toast(msg) }
   */
  constructor({ combat, vitals, prog, ctrl, ui = {} }) {
    this.combat = combat;
    this.vitals = vitals;
    this.prog = prog;
    this.ctrl = ctrl;
    this.ui = ui;

    this.cd = {};                    // id → 剩餘冷卻
    for (const s of SKILLS) this.cd[s.id] = 0;

    this.buff = null;                // { until, dmgMul, alwaysCrit }
    this.mugaReady = false;
    this.baseSpeedMul = ctrl?.speedMul ?? 1;
    this.baseMaxHp = vitals?.max ?? 120;
    this.markOn = false;

    combat.mods = this;              // Combat 每一擊會問這裡要倍率
    this._syncPassiveStats();
  }

  get level() { return this.prog?.state.charLv ?? 1; }

  /** 這個等級解鎖了哪些主動技 */
  get unlocked() { return SKILLS.filter(s => this.level >= s.unlock); }
  /** 這個等級生效中的被動 */
  get activePassives() { return PASSIVES.filter(p => this.level >= p.unlock); }
  has(id) {
    const p = PASSIVES.find(x => x.id === id);
    return !!p && this.level >= p.unlock;
  }

  /* ──────────────────────────────── Combat 的修正器介面 ── */

  /**
   * 這一擊的傷害倍率。Combat 每揮一刀只問一次。
   * @returns {{mul:number, crit:boolean}}
   */
  dmgMul({ wasSheathed }) {
    let mul = 1;
    let crit = false;

    if (this.has('battou') && wasSheathed) mul *= 1.5;      // 拔刀術
    if (this.markOn) mul *= 1.35;                            // 斑紋
    if (this.buff) mul *= this.buff.dmgMul;                  // 透き通る世界

    // 看穿要害：無我之境（必定）> 透世之器（機率）> 增益（必定）
    if (this.mugaReady) { crit = true; this.mugaReady = false; }
    else if (this.buff?.alwaysCrit) crit = true;
    else if (this.has('clarity') && Math.random() < 0.18) crit = true;

    if (crit) mul *= CRIT_MUL;
    return { mul, crit };
  }

  onSwing() { /* 目前不需要，留著讓被動有揮空也能觸發的掛點 */ }
  onHit() { /* 同上 */ }

  /* ────────────────────────────────────────── 主動技 ── */

  /** 依按鍵碼觸發（'Digit1'…）。回傳有沒有真的發動。 */
  pressKey(code) {
    const s = SKILLS.find(x => x.key === code);
    if (!s) return false;
    return this.use(s.id);
  }

  use(id) {
    const s = SKILLS.find(x => x.id === id);
    if (!s) return false;
    if (this.level < s.unlock) {
      this.ui.toast?.(`${s.zh} 需要 Lv.${s.unlock}`);
      return false;
    }
    if (this.cd[s.id] > 0) return false;

    if (s.buff) {
      this._applyBuff(s);
    } else if (!this.combat.useForm(s.form, s.dmgMul)) {
      return false;                 // 上一招還沒演完，冷卻不該被吃掉
    }
    this.cd[s.id] = s.cd;
    this.ui.banner?.(s.zh);
    return true;
  }

  _applyBuff(s) {
    this.buff = { t: s.buff.dur, dmgMul: s.buff.dmgMul, alwaysCrit: !!s.buff.alwaysCrit };
  }

  /* ──────────────────────────────────────────── 每幀 ── */

  update(dt) {
    for (const s of SKILLS) {
      if (this.cd[s.id] > 0) this.cd[s.id] = Math.max(0, this.cd[s.id] - dt);
    }
    if (this.buff) {
      this.buff.t -= dt;
      if (this.buff.t <= 0) this.buff = null;
    }

    // 無我之境：一段時間沒受傷就蓄滿，下一擊必定看穿要害
    this.mugaReady = this.has('muga') && this.vitals.sinceHurt >= MUGA_DELAY
      ? true : (this.mugaReady && this.vitals.sinceHurt >= MUGA_DELAY);

    // 斑紋：血量低於四成覺醒。用邊緣觸發，才好在覺醒的那一刻給提示。
    const wantMark = this.has('mark') && this.vitals.ratio < MARK_THRESHOLD && !this.vitals.dead;
    if (wantMark !== this.markOn) {
      this.markOn = wantMark;
      if (this.ctrl) this.ctrl.speedMul = this.baseSpeedMul * (wantMark ? 1.15 : 1);
      if (wantMark) this.ui.banner?.('斑　紋');
    }

    this.ui.skills?.(this.hudState());
  }

  /** 等級改變時重算被動帶來的常駐數值（最大血量之類） */
  _syncPassiveStats() {
    if (!this.vitals) return;
    this.vitals.setMax(this.baseMaxHp + (this.has('joutyuu') ? 30 : 0));
  }

  /** 升級時呼叫：重算常駐數值，並提示新解鎖的東西 */
  onLevelUp() {
    const beforeSkills = this.unlocked.length;
    const beforePassives = this.activePassives.length;
    this._syncPassiveStats();
    // 呼叫端在升級「之後」呼叫，所以這裡讀到的已經是新等級
    for (const s of SKILLS) {
      if (s.unlock === this.level) this.ui.toast?.(`習得　${s.zh}　（${s.slot}）`);
    }
    for (const p of PASSIVES) {
      if (p.unlock === this.level) this.ui.toast?.(`覺醒　${p.zh}`);
    }
    void beforeSkills; void beforePassives;
  }

  /** 給 HUD 的技能列狀態 */
  hudState() {
    return SKILLS.map(s => ({
      slot: s.slot, zh: s.zh, en: s.en,
      locked: this.level < s.unlock,
      unlock: s.unlock,
      cd: this.cd[s.id],
      cdMax: s.cd,
      active: s.buff && this.buff ? this.buff.t / s.buff.dur : 0,
    }));
  }
}

// forms.js 的索引在技能表裡是寫死的 —— 型錄如果重排，這裡會安靜地
// 指到別的招。載入時檢查一次，錯了就吵出來。
for (const s of SKILLS) {
  if (s.form == null) continue;
  if (!FORMS[s.form]) console.error(`[skills] ${s.id} 指向不存在的型 ${s.form}`);
}
