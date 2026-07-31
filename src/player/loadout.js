// 角色的「隨身裝備」—— HP/MP、戰鬥、技能、技能視窗，一次掛好。
//
// 為什麼要有這個檔：技能與血量是**角色內建**的，不是某張地圖的功能。
// 緣一走到哪都帶著他的十三型與那身天賦，所以每張圖都該有同一套東西。
// 在這之前這些是散在各地圖手抄的，抄漏一段就變成「換張圖就沒有技能」——
// 收成一個 installLoadout() 之後，新地圖一行就接上，也不會再分岔。
//
// 沒有戰鬥能力的角色（靈夢、魔理沙…）呼叫一樣安全：combat 與 skills 會是
// null，血條與技能列不會出現，行為跟以前完全一樣。
//
// 神社可以中途換角色，所以事件監聽**只在安裝時註冊一次**，內部透過
// closure 讀當下的 combat/skills；換角色後呼叫 rebuild() 換掉內容即可，
// 不會每換一次就多疊一組監聽器。

import { Vitals } from './vitals.js';
import { Combat } from '../combat/combat.js';
import { SkillSystem, SKILLS } from '../combat/skills.js';
import { SlashFX, SlashAudio } from '../fx/slash.js';
import { combatHUD, bindCombatInput } from '../combat/hud.js';
import { installSkillPanel } from '../ui/skillpanel.js';

/** 沒有怪的地圖（神社、里）用的空樁：招式照出，只是砍不到東西 */
export const NO_MOBS = {
  inSector: () => [],
  damage: () => false,
  aliveNear: () => 0,
  update() {},
};

/**
 * @param {object} deps
 * @param {() => object|null} deps.getSpec 現在扮演的角色（roster.js）
 * @param {() => object|null} deps.getCtrl 現在的 PlayerController
 * @param {THREE.Scene} deps.scene
 * @param {object}  deps.HUD        installHUD() 的回傳
 * @param {object}  deps.prog       Progression
 * @param {object}  [deps.mobs]     怪物群（省略 = 這張圖沒有怪）
 * @param {() => boolean} [deps.isBlocked] 選單／對話開著時不該吃戰鬥輸入
 * @param {() => void}    [deps.onDeath]   死亡後要把玩家搬到哪
 * @param {number}  [deps.maxHp=120] @param {number} [deps.maxMp=100]
 */
export function installLoadout({
  getSpec, getCtrl, scene, HUD, prog, mobs = null,
  isBlocked = () => false, onDeath = null,
  maxHp = 120, maxMp = 100,
}) {
  /* ── HP / MP（跨換角色保留，所以只建一次） ── */
  const vitals = new Vitals({
    max: maxHp, maxMp,
    hooks: {
      onChange: (v) => { if (kit.combat) HUD.vitals(v); },
      onHurt: () => {
        HUD.vitals(vitals, true);
        // 被打中會往後踉蹌一下，手感上要讀得到
        const c = getCtrl();
        if (c) {
          const a = c.yaw + Math.PI;
          c.vel.x += Math.sin(a) * 3.4;
          c.vel.z += Math.cos(a) * 3.4;
        }
      },
      onDeath: () => {
        HUD.deathVeil(true);
        setTimeout(() => {
          onDeath?.();
          getCtrl()?.vel.set(0, 0, 0);
          vitals.revive();
          HUD.deathVeil(false);
        }, 1900);
      },
    },
  });

  const fx = new SlashFX(scene);
  const audio = new SlashAudio();

  const kit = {
    vitals, fx,
    combat: null,
    skills: null,
    panel: null,

    /**
     * 依現在的角色重建戰鬥與技能。換角色（神社）之後呼叫。
     * 事件監聽不在這裡註冊 —— 見檔頭。
     */
    rebuild() {
      const spec = getSpec();
      const ctrl = getCtrl();
      const hasCombat = !!spec?.combat && !!ctrl;

      kit.combat = hasCombat
        ? new Combat(ctrl, mobs ?? NO_MOBS, fx, audio, combatHUD)
        : null;
      kit.skills = kit.combat
        ? new SkillSystem({
          combat: kit.combat, vitals, prog, ctrl,
          ui: {
            skills: (list) => HUD.skills(list),
            banner: (name) => combatHUD.formBanner(name),
            toast: (msg) => HUD.toast(msg),
          },
        })
        : null;

      combatHUD.reset();
      HUD.showCombatKeys(hasCombat);
      HUD.showFlyKeys(spec?.canFly !== false);
      if (hasCombat) {
        HUD.vitals(vitals);
        HUD.skills(kit.skills.hudState());
      }
      return kit;
    },

    /** 每幀呼叫。dt 是受頓挫壓慢的時間，rawDt 是真實時間。 */
    update(dt, rawDt = dt) {
      kit.combat?.update(dt, rawDt);
      fx.update(dt);
      vitals.update(dt);
      kit.skills?.update(dt);
    },
  };

  /* ── 輸入：只註冊一次 ── */
  kit.panel = installSkillPanel({
    getSkills: () => kit.skills,
    getCtrl,
    isBlocked,
  });
  // 技能面板開著時也不該出招 —— 面板是「另一個蓋在上面的介面」
  const blocked = () => isBlocked() || kit.panel.isOpen;
  bindCombatInput(() => kit.combat, getCtrl, blocked);

  window.addEventListener('keydown', (e) => {
    if (!kit.skills || !getCtrl()?.locked || blocked()) return;
    if (SKILLS.some(s => s.key === e.code)) {
      e.preventDefault();
      kit.skills.pressKey(e.code);
    }
  });

  kit.rebuild();
  return kit;
}
