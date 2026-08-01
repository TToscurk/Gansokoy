// 環境傷害區（hazard）—— 「地形即敵人」的那一半怪物。
//
// 魔法之森的孢子瘴氣、無名之丘的鈴蘭花海都不是實體怪：站進去就持續掉血，
// 畫面邊緣同時泛起該區的色調提示（毒紫、瘴綠…），玩家不用看血條也知道
// 自己站在不該站的地方。
//
// 傷害走 vitals.damage()，所以受擊無敵（0.75s）自然變成毒的節拍器 ——
// 不用另外做 DoT 計時，也不會跟怪物的攻擊疊成瞬殺。
//
// 邊緣提示是一層固定的 radial-gradient div，跟共用 HUD 的受擊紅屏同一個
// 做法（hud.js 的 #hurtFlash），但常駐淡入淡出而不是閃一下。

export class HazardZones {
  /**
   * @param {import('../player/vitals.js').Vitals} vitals
   */
  constructor(vitals) {
    this.vitals = vitals;
    this.zones = [];
    this.tint = 0;          // 邊緣提示的目前強度（0..1）
    this.tintColor = '128,40,160';

    this.el = document.createElement('div');
    this.el.style.cssText =
      'position:fixed;inset:0;z-index:57;pointer-events:none;opacity:0;transition:opacity .5s';
    document.body.appendChild(this.el);
  }

  /**
   * 圓形毒區。
   * @param {number} x @param {number} z @param {number} r
   * @param {number} dps 每秒傷害（實際節拍由無敵幀決定）
   * @param {object} [o]
   * @param {string} [o.color] 邊緣色調 'r,g,b'
   * @param {(x:number,z:number)=>boolean} [o.safe] 回 true 的地方挖空不算毒區。
   *   毒區的形狀是粗的（一個圓），但路是細的曲線 —— 用同一個判斷式同時
   *   決定「哪裡不長花」與「哪裡不中毒」，畫面上看到的和身上扣的才會一致。
   */
  addCircle(x, z, r, dps, o = {}) {
    this.zones.push({ kind: 'circle', x, z, r, dps, color: o.color, safe: o.safe });
    return this;
  }

  /**
   * 多邊形毒區（頂點 [x,z][]，射線法判內外）。o 同 addCircle。
   */
  addPolygon(pts, dps, o = {}) {
    this.zones.push({ kind: 'poly', pts, dps, color: o.color, safe: o.safe });
    return this;
  }

  _inside(zone, x, z) {
    if (zone.safe && zone.safe(x, z)) return false;
    if (zone.kind === 'circle') {
      return Math.hypot(x - zone.x, z - zone.z) < zone.r;
    }
    // 射線法
    const p = zone.pts;
    let inside = false;
    for (let i = 0, j = p.length - 1; i < p.length; j = i++) {
      const [xi, zi] = p[i], [xj, zj] = p[j];
      if ((zi > z) !== (zj > z) && x < ((xj - xi) * (z - zi)) / (zj - zi) + xi) {
        inside = !inside;
      }
    }
    return inside;
  }

  /** 每幀呼叫。pos 是玩家位置（THREE.Vector3）。 */
  update(dt, pos) {
    let hit = null;
    for (const zn of this.zones) {
      if (this._inside(zn, pos.x, pos.z)) { hit = zn; break; }
    }

    if (hit) {
      // dps 交給無敵幀節拍：每次真的扣到血就是一「口」毒。
      // 一口 = dps × 無敵時間(0.75s) 左右，濃度直覺跟 dps 成正比。
      this.vitals.damage(hit.dps * 0.75);
      if (hit.color) this.tintColor = hit.color;
    }

    const want = hit ? 1 : 0;
    if (want !== this.tint) {
      this.tint = want;
      this.el.style.background =
        `radial-gradient(ellipse at center, rgba(${this.tintColor},0) 46%, rgba(${this.tintColor},.5) 100%)`;
      this.el.style.opacity = want ? '1' : '0';
    }
  }
}
