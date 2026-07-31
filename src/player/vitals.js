// 玩家的 HP / MP —— 無雙戰鬥的前提。
//
// 在這之前這個專案嚴格說不算動作遊戲：妖精是無害的、玩家沒有血量，
// 出招純粹是演出。這個模組補上另外半邊 —— 會痛、會死、會爬起來，
// 而且出招要付出代價（MP）。
//
// 設計上刻意跟 UI 與地圖解耦：Vitals 只管數字與狀態機，畫面上的血條、
// 受擊紅屏、死亡黑幕都由呼叫端接 hooks。每張圖 new 一個，
// 怪物的攻擊回呼直接打進 damage()、技能的消耗打進 spend()。
//
// 存 localStorage 的是**比例**不是絕對值：上限會被等級與被動改動，
// 存絕對值的話升級一次就變殘血。死亡不扣進度 ——
// 這是割草遊戲不是魂系，死了就在入口重生、滿血再來。

const KEY = 'gansokoy:vitals:v2';

/** 受擊後的無敵時間（秒）。太短會被群怪瞬間磨死，太長就沒有壓力。 */
const IFRAME = 0.75;
/** 脫離戰鬥多久之後開始自然回血 */
const REGEN_DELAY = 6;
/** 自然回血速度（每秒 % 最大血量） */
const REGEN_RATE = 0.045;
/** MP 回復：呼吸法是持續在用的，隨時都在回，只是不快 */
const MP_REGEN_RATE = 0.075;   // 每秒 % 最大 MP
/** 剛用完技能的短暫停頓，免得連續放技能時 MP 條完全不動 */
const MP_REGEN_DELAY = 1.2;

export class Vitals {
  /**
   * @param {object} [opts]
   * @param {number} [opts.max=120]     最大血量
   * @param {number} [opts.maxMp=100]   最大 MP
   * @param {object} [opts.hooks]
   * @param {(v:Vitals)=>void}   [opts.hooks.onChange] HP/MP 變動（接 HUD）
   * @param {(dmg:number)=>void} [opts.hooks.onHurt]   受擊瞬間（接紅屏／震動）
   * @param {()=>void}           [opts.hooks.onDeath]  死亡（接黑幕／重生）
   */
  constructor({ max = 120, maxMp = 100, hooks = {} } = {}) {
    this.max = max;
    this.hp = max;
    this.maxMp = maxMp;
    this.mp = maxMp;
    this.hooks = hooks;
    this.iframe = 0;         // >0 = 無敵中
    this.sinceHurt = 999;    // 上次受傷到現在幾秒（回血用）
    this.sinceSpend = 999;   // 上次用 MP 到現在幾秒
    this.dead = false;
    this.totalTaken = 0;
    this._load();
  }

  _load() {
    try {
      const raw = JSON.parse(localStorage.getItem(KEY));
      if (raw && typeof raw.hpRatio === 'number' && raw.hpRatio > 0) {
        this.hp = Math.max(1, Math.round(this.max * Math.min(1, raw.hpRatio)));
      }
      if (raw && typeof raw.mpRatio === 'number' && raw.mpRatio >= 0) {
        this.mp = Math.round(this.maxMp * Math.min(1, raw.mpRatio));
      }
    } catch { /* 私隱模式或壞資料，滿血開始 */ }
  }

  _save() {
    try {
      localStorage.setItem(KEY, JSON.stringify({
        hpRatio: this.hp / this.max,
        mpRatio: this.mp / this.maxMp,
      }));
    } catch { /* 私隱模式 */ }
  }

  get ratio() { return Math.max(0, this.hp / this.max); }
  get mpRatio() { return Math.max(0, this.mp / this.maxMp); }
  /** 無敵中或已死都不該再吃傷害 */
  get invulnerable() { return this.iframe > 0 || this.dead; }

  /**
   * 吃一次傷害。
   * @returns {boolean} 這次有沒有真的扣到血
   */
  damage(amount) {
    if (this.invulnerable || amount <= 0) return false;
    this.hp = Math.max(0, this.hp - amount);
    this.totalTaken += amount;
    this.iframe = IFRAME;
    this.sinceHurt = 0;
    this.hooks.onHurt?.(amount);
    this.hooks.onChange?.(this);
    this._save();
    if (this.hp <= 0) {
      this.dead = true;
      this.hooks.onDeath?.();
    }
    return true;
  }

  heal(amount) {
    if (this.dead || amount <= 0) return;
    const before = this.hp;
    this.hp = Math.min(this.max, this.hp + amount);
    if (this.hp !== before) {
      this.hooks.onChange?.(this);
      this._save();
    }
  }

  /** MP 夠不夠 */
  canSpend(cost) { return this.mp >= cost; }

  /**
   * 花 MP。不夠就不扣、回 false —— 呼叫端據此擋掉技能發動。
   * @returns {boolean}
   */
  spend(cost) {
    if (cost <= 0) return true;
    if (this.mp < cost) return false;
    this.mp -= cost;
    this.sinceSpend = 0;
    this.hooks.onChange?.(this);
    this._save();
    return true;
  }

  restoreMp(amount) {
    if (amount <= 0) return;
    const before = this.mp;
    this.mp = Math.min(this.maxMp, this.mp + amount);
    if (this.mp !== before) {
      this.hooks.onChange?.(this);
      this._save();
    }
  }

  /** 死亡後的復活（呼叫端負責把玩家搬回入口） */
  revive() {
    this.dead = false;
    this.hp = this.max;
    this.mp = this.maxMp;
    this.iframe = 1.5;        // 復活後給一點喘息
    this.sinceHurt = 0;
    this.hooks.onChange?.(this);
    this._save();
  }

  /** 上限改變（升級、被動技能）時保持當前比例 */
  setMax(max) {
    if (max === this.max) return;
    const r = this.ratio;
    this.max = max;
    this.hp = Math.max(1, Math.round(max * r));
    this.hooks.onChange?.(this);
  }

  setMaxMp(maxMp) {
    if (maxMp === this.maxMp) return;
    const r = this.mpRatio;
    this.maxMp = maxMp;
    this.mp = Math.round(maxMp * r);
    this.hooks.onChange?.(this);
  }

  update(dt) {
    if (this.iframe > 0) this.iframe -= dt;
    if (this.dead) return;
    this.sinceHurt += dt;
    this.sinceSpend += dt;

    // 脫離戰鬥一段時間後緩慢回血 —— 割草遊戲不該逼玩家回城補血
    if (this.sinceHurt > REGEN_DELAY && this.hp < this.max) {
      this.heal(this.max * REGEN_RATE * dt);
    }
    // MP 隨時都在回（呼吸法是持續在用的），只是剛放完技能會停一下
    if (this.sinceSpend > MP_REGEN_DELAY && this.mp < this.maxMp) {
      this.restoreMp(this.maxMp * MP_REGEN_RATE * dt);
    }
  }
}
