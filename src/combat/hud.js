// 戰鬥 HUD 與輸入 —— 每張地圖共用。
//
// 一張地圖要讓角色能出招，需要的頁面端零件都一樣：
//   1. 三個 HUD 元素（#formBanner 型名橫幅、#combo 連擊、#charge 蓄力條）
//   2. 滑鼠左鍵（點=出招、按住=蓄力大招）與 R（拔刀/納刀）的監聽
// 這裡把兩者抽成共用：main.js（神社）與 trail.js（獸道）都直接掛，
// 之後的新地圖也一樣 —— 免得每張圖手抄一份、漏一段就變成「換圖不能出招」。

/** HUD 更新器。頁面上缺元素時安靜跳過（畫面不能因為少條蓄力條而全黑）。 */
export const combatHUD = {
  formBanner(name) {
    const el = document.getElementById('formBanner');
    if (!el) return;
    el.textContent = name;
    el.classList.remove('on');
    void el.offsetWidth;          // 重播 CSS 動畫
    el.classList.add('on');
  },
  charge(r) {
    const el = document.getElementById('charge');
    if (!el) return;
    el.classList.toggle('on', r > 0.06);
    el.classList.toggle('full', r >= 1);
    const fill = el.querySelector('.f');
    if (fill) fill.style.width = (r * 100).toFixed(1) + '%';
  },
  combo(n) {
    const el = document.getElementById('combo');
    if (!el) return;
    el.classList.toggle('on', n >= 2);
    if (n >= 2) {
      el.querySelector('.n').textContent = n;
      el.classList.remove('tick');
      void el.offsetWidth;
      el.classList.add('tick');
    }
  },
  /** 換角色/換圖時歸零殘留的 HUD 狀態 */
  reset() {
    this.charge(0);
    const combo = document.getElementById('combo');
    if (combo) combo.classList.remove('on');
  },
};

/**
 * 綁定戰鬥輸入（左鍵出招/蓄力、R 拔刀納刀）。
 * @param {() => import('./combat.js').Combat|null} getCombat 現在的戰鬥控制器（沒有=角色無技能）
 * @param {() => object|null} getCtrl 現在的 PlayerController
 * @param {() => boolean} [isBlocked] 對話中/編輯器開著等不該出招的時機
 */
export function bindCombatInput(getCombat, getCtrl, isBlocked = () => false) {
  window.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    const combat = getCombat();
    if (!combat || !getCtrl()?.locked || isBlocked()) return;
    combat.tryAttack();
    combat.holdStart();
  });
  const endHold = () => getCombat()?.holdEnd();
  window.addEventListener('mouseup', (e) => { if (e.button === 0) endHold(); });
  window.addEventListener('blur', endHold);
  window.addEventListener('keydown', (e) => {
    if (e.code !== 'KeyR') return;
    const combat = getCombat();
    if (!combat || !getCtrl()?.locked || isBlocked()) return;
    combat.toggleSheath();
  });
}
