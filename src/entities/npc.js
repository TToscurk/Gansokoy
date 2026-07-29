import * as THREE from 'three';
import { buildCharacter, animateCharacter } from './model.js';
import { ROSTER } from './roster.js';
import { REGION_BY_ID, WORLD } from '../config.js';
import { groundHeight } from '../world/terrain.js';

/** 可以對話的距離。main.js 與 shrine-spawn.js 都用這個值，不要各自寫死。 */
export const TALK_RANGE = 4.2;
// 26 位住民散布全圖，不可能同時入鏡 —— 超過這個距離整隻隱藏、
// 連待機動畫都不跑，同屏負擔跟 16 位的時代一樣。
const CULL_DIST = 260;
// 名牌的顯示半徑（只有最近的一位會拿到名牌，見 update）
const LABEL_RANGE = 12;

function nameplate(zh, en) {
  const c = document.createElement('canvas');
  c.width = 512; c.height = 128;
  const g = c.getContext('2d');
  g.clearRect(0, 0, 512, 128);

  g.font = '600 46px "Noto Sans TC","Microsoft JhengHei",sans-serif';
  g.textAlign = 'center';
  g.shadowColor = 'rgba(0,0,0,.9)';
  g.shadowBlur = 12;
  g.fillStyle = '#fff';
  g.fillText(zh, 256, 56);

  g.font = '400 20px sans-serif';
  g.letterSpacing = '4px';
  g.fillStyle = 'rgba(220,200,230,.8)';
  g.fillText(en, 256, 92);

  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  const m = new THREE.SpriteMaterial({
    map: t, transparent: true, opacity: 0, depthTest: false, depthWrite: false, fog: false,
  });
  const s = new THREE.Sprite(m);
  s.scale.set(3.2, 0.8, 1);
  s.renderOrder = 999;
  return s;
}

export class NPCManager {
  /**
   * @param {THREE.Scene} scene
   * @param {THREE.Scene} [labelScene] 名牌要放的場景。名牌是 depthTest:false 的
   *   sprite，不進深度緩衝；留在主場景裡會被 GTAO 的法線預渲染算出垃圾遮蔽值
   *   而變成純黑方塊。交給 main.js 在後製之後單獨畫。省略時退回主場景。
   */
  constructor(scene, labelScene) {
    this.scene = scene;
    this.labelScene = labelScene ?? scene;
    this.npcs = [];            // 現在這張圖上的住民
    this.nearest = null;
    this.enabled = true;
    // 建好的角色快取（id → 記錄）。分圖切換時重用，不重建 ——
    // 一個角色的程序式建模不便宜，每次切圖重造 34 位會讓過場卡住。
    this._cache = new Map();
    this._origin = { x: 0, z: 0 };
  }

  /** 建一位（或從快取取回）。位置在世界座標，之後由 setRoster 換算。 */
  _ensure(spec) {
    let rec = this._cache.get(spec.id);
    if (rec) return rec;

    const root = buildCharacter(spec);
    root.rotation.y = spec.face ?? 0;
    const plate = nameplate(spec.zh, spec.en);
    const outlines = [];
    root.traverse(o => { if (o.name === 'outline') outlines.push(o); });

    rec = {
      spec, root, plate, outlines,
      pos: new THREE.Vector3(),
      talkIndex: 0,
      baseYaw: spec.face ?? 0,
    };
    this._cache.set(spec.id, rec);
    return rec;
  }

  /**
   * 換上這張圖的住民（SCENE_MANAGER_SPEC §4 #8）。
   *
   * @param ids    要出場的角色 id 陣列；null = 全員（legacy_open 用）
   * @param origin 這張圖的原點在世界座標的位置。角色的家寫在 roster 裡
   *               （地區座標 + 位移，都是世界座標），減掉原點就是局部座標。
   *
   * 落地高度用 groundHeight()，所以**必須在 manager 換好高度場之後呼叫** ——
   * 早一步的話整批人會站在上一張圖的地面高度上。
   */
  setRoster(ids, origin = { x: 0, z: 0 }, bounds = 0) {
    this._origin = origin;
    const want = ids ? new Set(ids) : null;

    // 名單裡有 roster 沒有的 id = 打錯字，靜靜消失最難查
    if (want) {
      const known = new Set(ROSTER.map(s => s.id));
      for (const id of want) {
        if (!known.has(id)) console.error(`[npc] 名單裡沒有這個角色：${id}`);
      }
    }

    // 先把上一張圖的人請下場
    for (const n of this.npcs) {
      this.scene.remove(n.root);
      this.labelScene.remove(n.plate);
    }
    this.npcs = [];
    this.nearest = null;

    for (const spec of ROSTER) {
      if (want && !want.has(spec.id)) continue;
      const reg = REGION_BY_ID[spec.region];
      if (!reg) continue;

      const x = reg.x + spec.offset[0] - origin.x;
      const z = reg.z + spec.offset[1] - origin.z;
      const ground = Math.max(groundHeight(x, z), WORLD.waterLevel);
      const y = ground + (spec.float ? (spec.floatY ?? 0.8) : 0);

      const rec = this._ensure(spec);
      rec.root.position.set(x, y, z);
      rec.plate.position.set(x, y + 2.35, z);
      rec.pos.set(x, y, z);
      rec.root.rotation.y = rec.baseYaw;
      // 距離剔除是邊緣觸發的，換圖後強迫下一幀重新判定
      rec.culled = null;
      rec.outlineOn = null;
      rec.root.visible = false;
      rec.plate.visible = false;

      // 住在別區的人被列進來時，換算後會落在圖外很遠的地方 ——
      // 畫面上什麼都沒有，最難查。直接報出來。
      if (bounds && (Math.abs(x) > bounds || Math.abs(z) > bounds)) {
        console.error(`[npc] ${spec.id}（家在 ${spec.region}）落在圖外 ` +
                      `(${x.toFixed(0)}, ${z.toFixed(0)})，半徑上限 ${bounds}`);
      }

      this.scene.add(rec.root);
      this.labelScene.add(rec.plate);
      this.npcs.push(rec);
    }
    return this.npcs.length;
  }

  update(t, playerPos, camera) {
    let best = null, bestD = TALK_RANGE;

    if (this.enabled === false) { this.nearest = null; return null; }

    // 名牌只給最近的一位。境內站了三十幾人，只要放寬到「附近都顯示」，
    // 十來塊名牌就會在畫面上疊成一團看不懂 —— 而且按 E 也只會跟最近的講話。
    let labelled = null, labelledD = LABEL_RANGE;
    for (const n of this.npcs) {
      const d = n.pos.distanceTo(playerPos);
      if (d < labelledD) { labelledD = d; labelled = n; }
    }

    for (const n of this.npcs) {
      const d = n.pos.distanceTo(playerPos);

      // 距離剔除：直接整隻關掉，動畫與描邊邏輯全部跳過
      const visible = d < CULL_DIST;
      if (n.culled !== !visible) {
        n.culled = !visible;
        n.root.visible = visible;
        if (!visible) n.plate.visible = false;
      }
      if (!visible) continue;

      animateCharacter(n.root, t, 0);

      // 遠處關掉描邊：省下的 draw call 比看得出來的差異多得多。
      // 70 公尺等於「境內所有人都開」—— 34 位角色的描邊就是 242 個 mesh、
      // 27 萬個三角形、約 13ms。收到 20 公尺，只有真的走近的人有描邊。
      const wantOutline = d < 20;
      if (n.outlineOn !== wantOutline) {
        n.outlineOn = wantOutline;
        for (const o of n.outlines) o.visible = wantOutline;
      }

      // 名牌：只有最近那位會浮現，其他人淡出
      const vis = n === labelled ? 1 - Math.min(1, Math.max(0, (d - 6) / 6)) : 0;
      n.plate.material.opacity += (vis - n.plate.material.opacity) * 0.16;
      n.plate.visible = n.plate.material.opacity > 0.01;

      // 玩家靠近時轉頭看你
      if (d < 9) {
        const want = Math.atan2(playerPos.x - n.pos.x, playerPos.z - n.pos.z);
        let diff = want - n.root.rotation.y;
        while (diff > Math.PI) diff -= Math.PI * 2;
        while (diff < -Math.PI) diff += Math.PI * 2;
        n.root.rotation.y += diff * 0.045;
      } else {
        let diff = n.baseYaw - n.root.rotation.y;
        while (diff > Math.PI) diff -= Math.PI * 2;
        while (diff < -Math.PI) diff += Math.PI * 2;
        n.root.rotation.y += diff * 0.02;
      }

      if (d < bestD) { bestD = d; best = n; }
    }

    this.nearest = best;
    return best;
  }

  /** 取出下一段對話，並把指標推進 */
  nextTalk(npc) {
    const talks = npc.spec.talks;
    const lines = talks[npc.talkIndex % talks.length];
    npc.talkIndex++;
    return lines;
  }
}
