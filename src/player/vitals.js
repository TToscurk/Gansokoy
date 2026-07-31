// 玩家的血量 —— 無雙戰鬥的前提。
//
// 在這之前這個專案嚴格說不算動作遊戲：妖精是無害的、玩家沒有血量，
// 出招純粹是演出。這個模組補上另外半邊 —— 會痛、會死、會爬起來。
//
// 設計上刻意跟 UI 與地圖解耦：Vitals 只管數字與狀態機，畫面上的血條、
// 受擊紅屏、死亡黑幕都由呼叫端接 hooks。每張有怪的地圖 new 一個，
// 怪物的攻擊回呼直接打進 damage()。
//
// 血量存 localStorage（跟等級同一個規格），但**死亡不會扣進度** ——
// 這是割草遊戲不是魂系，死了就在入口重生、滿血再來。

const KEY = 'gansokoy:vitals:v1';

/** 受擊後的無敵時間（秒）。太短會被群怪瞬間磨死，太長就沒有壓力。 */
const IFRAME = 0.75;
/** 脫離戰鬥多久之後開始自然回血 */
const REGEN_DELAY = 6;
/** 自然回血速度（每秒 % 最大血量） */
const REGEN_RATE = 0.045;

export class Vitals {
  /**
   * @param {object} [opts]
   * @param {number} [opts.max=120]      最大血量
   * @param {object} [opts.hooks]
   * @param {(hp:number,max:number)=>void} [opts.hooks.onChange] 血量變動（接血條）
   * @param {(dmg:number)=>void}           [opts.hooks.onHurt]   受擊瞬間（接紅屏／震動）
   * @param {()=>void}                     [opts.hooks.onDeath]  死亡（接黑幕／重生）
   */
  constructor({ max = 120, hooks = {} } = {}) {
    this.max = max;
    this.hp = max;
    this.hooks = hooks;
    this.iframe = 0;         // >0 = 無敵中
    this.sinceHurt = 999;    // 上次受傷到現在幾秒（回血用）
    this.dead = false;
    this.totalTaken = 0;
    this._load();
  }

  _load() {
    try {
      const raw = JSON.parse(localStorage.getItem(KEY));
      // 只還原血量比例：最大血量可能因為等級/技能而改變
      if (raw && typeof raw.ratio === 'number' && raw.ratio > 0) {
        this.hp = Math.max(1, Math.round(this.max * Math.min(1, raw.ratio)));
      }
    } catch { /* 私隱模式或壞資料，滿血開始 */ }
  }

  _save() {
    try { localStorage.setItem(KEY, JSON.stringify({ ratio: this.hp / this.max })); }
    catch { /* 私隱模式 */ }
  }

  get ratio() { return Math.max(0, this.hp / this.max); }
  /** 無敵中或已死都不該再吃傷害 */
  get invulnerable() { return this.iframe > 0 || this.dead; }

  /**
   * 吃一次傷害。
   * @param {number} amount
   * @returns {boolean} 這次有沒有真的扣到血
   */
  damage(amount) {
    if (this.invulnerable || amount <= 0) return false;
    this.hp = Math.max(0, this.hp - amount);
    this.totalTaken += amount;
    this.iframe = IFRAME;
    this.sinceHurt = 0;
    this.hooks.onHurt?.(amount);
    this.hooks.onChange?.(this.hp, this.max);
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
      this.hooks.onChange?.(this.hp, this.max);
      this._save();
    }
  }

  /** 死亡後的復活（呼叫端負責把玩家搬回入口） */
  revive() {
    this.dead = false;
    this.hp = this.max;
    this.iframe = 1.5;        // 復活後給一點喘息
    this.sinceHurt = 0;
    this.hooks.onChange?.(this.hp, this.max);
    this._save();
  }

  /** 最大血量改變（升級、被動技能）時保持當前比例 */
  setMax(max) {
    if (max === this.max) return;
    const r = this.ratio;
    this.max = max;
    this.hp = Math.max(1, Math.round(max * r));
    this.hooks.onChange?.(this.hp, this.max);
  }

  update(dt) {
    if (this.iframe > 0) this.iframe -= dt;
    if (this.dead) return;
    this.sinceHurt += dt;
    // 脫離戰鬥一段時間後緩慢回血 —— 割草遊戲不該逼玩家回城補血
    if (this.sinceHurt > REGEN_DELAY && this.hp < this.max) {
      this.heal(this.max * REGEN_RATE * dt);
    }
  }
}
