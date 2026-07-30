// 角色等級 + 技能等級 —— 跨地圖共用的成長系統。
//
// 資料存 localStorage（重整、換地圖都保留）：
//   { charLv, charXp, skills: { [skillId]: { lv, xp } }, kills }
//
// 現在只有繼國緣一的「日之呼吸」一個技能；之後為其他角色設計技能時，
// 用各自的 skillId 呼叫 onHit/onKill 即可，資料結構天生支援多技能。
//
// 等級的作用：加傷害。dmgMul() 給 combat 的命中傷害乘上去 ——
// 角色等級每級 +8%、技能等級每級 +12%。

const KEY = 'gansokoy:progress:v1';

function load() {
  try {
    const raw = JSON.parse(localStorage.getItem(KEY));
    if (raw && typeof raw === 'object') {
      return {
        charLv: raw.charLv ?? 1, charXp: raw.charXp ?? 0,
        skills: raw.skills ?? {}, kills: raw.kills ?? 0,
      };
    }
  } catch { /* 壞資料就重來 */ }
  return { charLv: 1, charXp: 0, skills: {}, kills: 0 };
}

/** 升到下一級需要的經驗 */
const charXpNeed = (lv) => 40 + (lv - 1) * 30;
const skillXpNeed = (lv) => 30 + (lv - 1) * 45;

export class Progression {
  /**
   * @param {object} [hooks]
   * @param {(msg:string)=>void} [hooks.onLevelUp] 升級時的提示（toast）
   */
  constructor(hooks = {}) {
    this.hooks = hooks;
    this.state = load();
  }

  _save() {
    try { localStorage.setItem(KEY, JSON.stringify(this.state)); } catch { /* 私隱模式 */ }
  }

  _skill(id) {
    return (this.state.skills[id] ??= { lv: 1, xp: 0 });
  }

  /** 命中一隻怪：技能練度小漲 */
  onHit(skillId, skillName = skillId) {
    const s = this._skill(skillId);
    s.xp += 2;
    this._checkSkill(s, skillName);
    this._save();
  }

  /** 擊殺：角色經驗 + 技能練度 */
  onKill(skillId, skillName = skillId) {
    this.state.kills++;
    this.state.charXp += 14;
    const s = this._skill(skillId);
    s.xp += 6;
    while (this.state.charXp >= charXpNeed(this.state.charLv)) {
      this.state.charXp -= charXpNeed(this.state.charLv);
      this.state.charLv++;
      this.hooks.onLevelUp?.(`等級提升！Lv.${this.state.charLv}`);
    }
    this._checkSkill(s, skillName);
    this._save();
  }

  _checkSkill(s, name) {
    while (s.xp >= skillXpNeed(s.lv)) {
      s.xp -= skillXpNeed(s.lv);
      s.lv++;
      this.hooks.onLevelUp?.(`${name} 練度提升！Lv.${s.lv}`);
    }
  }

  /** 傷害倍率：角色每級 +8%、指定技能每級 +12% */
  dmgMul(skillId) {
    const s = this._skill(skillId);
    return 1 + 0.08 * (this.state.charLv - 1) + 0.12 * (s.lv - 1);
  }

  /** HUD 徽章文字，例如「Lv.3　日之呼吸 Lv.2」 */
  badge(skillId, skillName) {
    const parts = [`Lv.${this.state.charLv}`];
    if (skillId) parts.push(`${skillName} Lv.${this._skill(skillId).lv}`);
    return parts.join('　');
  }

  /** 把徽章寫進 #lvlBadge（頁面沒有這個元素就跳過） */
  renderBadge(skillId, skillName) {
    const el = document.getElementById('lvlBadge');
    if (el) el.textContent = this.badge(skillId, skillName);
  }
}

/**
 * 把「真怪物群」包一層：命中傷害吃成長倍率、擊殺回報經驗。
 * combat.js 只認識 mobs 介面（inSector/damage/aliveNear/update），
 * 完全不用知道成長系統存在 —— 之後每張有怪的地圖都這樣包一次。
 */
export function progressMobs(real, prog, skillId, skillName) {
  return {
    inSector: (o, yaw, range, arc) => real.inSector(o, yaw, range, arc),
    damage(m, dmg, dx, dz) {
      const killed = real.damage(m, dmg * prog.dmgMul(skillId), dx, dz);
      if (killed) prog.onKill(skillId, skillName);
      else prog.onHit(skillId, skillName);
      prog.renderBadge(skillId, skillName);
      return killed;
    },
    aliveNear: (p, r) => real.aliveNear(p, r),
    update: (dt, t, p) => real.update(dt, t, p),
  };
}
