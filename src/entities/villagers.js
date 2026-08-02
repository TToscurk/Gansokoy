// 里民路人 —— 在街上來來去去的無名村民。
//
// 他們不是名冊（roster）裡的角色：沒有名字、不能對話、不會被場景編輯器
// 擺放，純粹是讓里看起來「有人住」的背景人流。外觀用同一套程序化建模
// （buildCharacter）隨機生成，走路動畫也共用 animateCharacter。
//
// 行走方式：街道被描述成一張路點圖（節點 + 相鄰關係），每個人隨機挑
// 下一個相鄰路點走過去，偶爾在店門口停下來發呆一下再繼續。因為路點
// 全部落在街道上，他們不會走進建築物裡 —— 不需要另外做避障。

import * as THREE from 'three';
import { buildCharacter, animateCharacter, setCharacterFar } from './model.js';
import { CHAR_LOD } from '../config.js';

// 村民的衣著配色（樸素的和服色系，跟主要角色的鮮豔配色區隔開）。
// 加了藍染（縕袍）、柿澀、鶯、江戶紫這些傳統色，讓街上不會一片土黃。
const HAIR = [0x2a2118, 0x3a2c20, 0x4a3a28, 0x1e1a18, 0x5a4632, 0x33281e];
const HAIR_ELDER = [0x9a948a, 0xb8b2a6, 0x7a7268];
const OUTFIT = [
  0x6a6250, 0x7a6a52, 0x585f68, 0x6e5a4a, 0x4a5560,
  0x8a7a5e, 0x5c6650, 0x74604e, 0x3f4a52, 0x7d6a6a,
  0x3a4a6a, 0x8a5a3a, 0x5a6a4a, 0x6a4a62, 0x4a5a5a,   // 藍染、柿澀、鶯、江戶紫、青鈍
];
const OUTFIT_KID = [0xb06a4a, 0x5a7a9a, 0x8a9a5a, 0xa8788a, 0xc09a5a];  // 小孩衣服亮一點
const ACCENT = [0x9a5a4a, 0x4a6a7a, 0x7a6a3a, 0x6a4a5a, 0x3a5a4a, 0xa8783a];
const SKIN = [0xf0cead, 0xe8c4a4, 0xdcb896, 0xf4d8bc];
const HAIRSTYLE = ['short', 'long', 'longTied', 'bob', 'longStraight', 'braid'];
const HAIRSTYLE_KID = ['short', 'bob', 'twin', 'braid'];

const pick = (arr, r) => arr[(r * arr.length) | 0];

/** 決定性亂數：同一個 index 每次重整都長一樣，畫面不會每次刷新都跳動 */
function rnd(seed) {
  const v = Math.sin(seed * 91.7 + 43.3) * 37219.1;
  return v - Math.floor(v);
}

/**
 * 生一位村民的外觀＋行為參數。三種族群：
 *   小孩（矮、衣服亮、跑得快）、老人家（灰髮、慢、駝一點）、大人。
 *   大人約三成戴斗笠（農家、旅人的味道）。
 */
function villagerSpec(i) {
  const r1 = rnd(i * 3.1), r2 = rnd(i * 7.7), r3 = rnd(i * 13.3), r4 = rnd(i * 5.9);
  const roleRoll = rnd(i * 17.9);
  const role = roleRoll < 0.2 ? 'kid' : roleRoll < 0.38 ? 'elder' : 'adult';

  const outfit = role === 'kid' ? pick(OUTFIT_KID, r2) : pick(OUTFIT, r2);
  const spec = {
    id: `villager${i}`, role,
    hair: role === 'kid' ? pick(HAIRSTYLE_KID, r1) : pick(HAIRSTYLE, r1),
    hat: role === 'adult' && rnd(i * 23.7) < 0.3 ? 'kasa' : 'none',
    wings: 'none', prop: 'none', float: false,
    scale: role === 'kid' ? 0.66 + r4 * 0.1
      : role === 'elder' ? 0.88 + r4 * 0.06
      : 0.94 + r4 * 0.16,
    palette: {
      hair: role === 'elder' ? pick(HAIR_ELDER, r1) : pick(HAIR, r1),
      outfit, outfit2: outfit,
      accent: pick(ACCENT, r3),
      legs: 0xe8e0d0, shoes: 0x4a3a2c,
      eyes: 0x4a3a30, skin: pick(SKIN, r4),
    },
  };
  // 走路速度也跟著族群走：小孩用小跑的、老人家慢慢走
  spec.walkSpeed = role === 'kid' ? 2.3 + rnd(i * 31.1) * 1.1
    : role === 'elder' ? 0.9 + rnd(i * 31.1) * 0.5
    : 1.5 + rnd(i * 31.1) * 1.3;
  return spec;
}

export class VillagerCrowd {
  /**
   * @param {THREE.Scene} scene
   * @param {(x:number,z:number)=>number} heightFn
   * @param {object} graph 路點圖 { nodes:[[x,z],...], links:[[a,b],...] }
   * @param {number} [count=22]
   * @param {number} [warm=12] 建構時先做幾位；其餘每幀補一位（見 update）
   * @param {object[]} [colliders] 地圖的碰撞盒。給了就會把路人推出建築 ——
   *   路點圖是手繪的，難免有幾條連線從屋角切過去，走到那裡的人會半個身體
   *   插在牆裡。這裡不改圖，直接在位置上把人推出去（見 _unstick）。
   */
  constructor(scene, heightFn, graph, count = 22, warm = 12, colliders = null) {
    this.scene = scene;
    this.heightFn = heightFn;
    // 只留擋人的那些（有 hw 的矩形、有 r 的柱），並預先算好篩選半徑
    this.colliders = (colliders ?? []).filter(c => c.hw != null || c.r != null);
    this.nodes = graph.nodes.map(([x, z]) => new THREE.Vector2(x, z));
    // 相鄰表：雙向
    this.adj = this.nodes.map(() => []);
    for (const [a, b] of graph.links) { this.adj[a].push(b); this.adj[b].push(a); }

    this.root = new THREE.Group();
    scene.add(this.root);
    this.visible = true;
    this.people = [];

    // 一位路人的程序化建模不便宜（建幾何 → 合併 → 生描邊外殼），
    // 五十幾位一次做完會讓進圖卡好幾秒。所以只先做 warm 位，
    // 其餘每幀補一位 —— 玩家走進里的頭幾秒街上會陸續多出人來，
    // 比盯著讀取畫面等五秒好得多。
    this.total = count;
    this._pending = 0;
    for (let i = 0; i < Math.min(warm, count); i++) this._spawn(i);
    this._pending = Math.min(warm, count);
  }

  /** 生第 i 位路人 */
  _spawn(i) {
    const spec = villagerSpec(i);
    const model = buildCharacter(spec);
    const outlines = [];
    model.traverse(o => { if (o.name === 'outline') outlines.push(o); });
    this.root.add(model);

    // 起點：隨機一個路點，目標：它的隨機鄰居
    const from = (rnd(i * 2.3) * this.nodes.length) | 0;
    const to = this._nextFrom(from, -1, rnd(i * 4.1));
    this.people.push({
      model, outlines, from, to,
      pos: this.nodes[from].clone(),
      speed: spec.walkSpeed,
      role: spec.role,
      phase: rnd(i * 6.4) * 10,
      idle: rnd(i * 9.2) * 6,        // 一開始各自錯開，不會整群同步
      outlineOn: null,
    });
  }

  _nextFrom(node, avoid, r) {
    const opts = this.adj[node];
    if (!opts.length) return node;
    // 盡量不要立刻掉頭（只有死路才回頭）
    const fwd = opts.filter(n => n !== avoid);
    const list = fwd.length ? fwd : opts;
    return list[(r * list.length) | 0];
  }

  /** 顯示／隱藏所有路人（場景編輯器的開關用） */
  setVisible(on) {
    this.visible = on;
    this.root.visible = on;
  }

  update(dt, t, playerPos) {
    if (!this.visible) return;

    // 每幀補一位還沒生出來的路人（見建構式的說明）
    if (this._pending < this.total) {
      this._spawn(this._pending);
      this._pending++;
    }

    for (const p of this.people) {
      // 細節層級要在動畫之前決定 —— 遠景的人整隻是一個烘死姿勢的網格，
      // 再去算手腳擺動只是白花 CPU
      const far = this._lod(p, playerPos);

      // 停下來發呆（站直、放掉前傾）
      if (p.idle > 0) {
        p.idle -= dt;
        p.model.position.y = this.heightFn(p.pos.x, p.pos.y);
        p.model.rotation.x = p.role === 'elder' ? 0.05 : 0;
        if (!far) animateCharacter(p.model, t + p.phase, 0);
        continue;
      }

      const target = this.nodes[p.to];
      const dx = target.x - p.pos.x, dz = target.y - p.pos.y;
      const d = Math.hypot(dx, dz);

      if (d < 0.45) {
        // 到站：挑下一個路點，偶爾在這裡停一下（像在看店）
        const r = Math.random();
        const prev = p.from;
        p.from = p.to;
        p.to = this._nextFrom(p.to, prev, Math.random());
        if (r < 0.22) p.idle = 1.5 + Math.random() * 3.5;
        continue;
      }

      // --- 避障（品質升級書・升級 3）---
      // 舊版是節點之間直線走，路上有東西就頂著磨蹭。這裡往前探 2 公尺，
      // 撞到就沿障礙的切線偏轉。用圓查詢而不是 raycast —— colliders 本來
      // 就是圓柱／方盒的參數，直接算比丟射線便宜得多。
      let ux = dx / d, uz = dz / d;
      const steer = this._avoid(p.pos.x, p.pos.y, ux, uz);
      ux = steer.x; uz = steer.z;

      const step = Math.min(d, p.speed * dt);
      p.pos.x += ux * step;
      p.pos.y += uz * step;

      // --- 卡死偵測 ---
      // 連續 2 秒位移不到 0.3 公尺就是卡住了（被兩面牆夾住、或切線方向
      // 又是另一個障礙）。放棄目前目標，回到最近的路網節點重新選路。
      p._stuckT = (p._stuckT ?? 0) + dt;
      if (p._stuckT >= 2) {
        const moved = Math.hypot(p.pos.x - (p._sx ?? p.pos.x), p.pos.y - (p._sy ?? p.pos.y));
        if (moved < 0.3) {
          let best = -1, bestD = Infinity;
          for (let i = 0; i < this.nodes.length; i++) {
            const n = this.nodes[i];
            const nd = Math.hypot(n.x - p.pos.x, n.y - p.pos.y);
            if (nd < bestD) { bestD = nd; best = i; }
          }
          if (best >= 0) { p.from = p.to; p.to = best; }
        }
        p._stuckT = 0; p._sx = p.pos.x; p._sy = p.pos.y;
      }

      // 走路動畫：animateCharacter 的擺幅是按「玩家速度」調的（5.5 才滿幅），
      // 村民走 1~3 m/s 直接餵會只擺一點點、看起來像用飄的。乘個係數讓
      // 手腳確實擺起來，再疊一個跟步頻同步的縱向彈跳 —— 腳跟著地的重量感。
      const animSpeed = p.speed * 2.6;
      const w = Math.min(1, animSpeed / 5.5);
      const cad = 9 * Math.max(0.35, w);                       // 與 animateCharacter 的步頻同一條公式
      const bob = Math.abs(Math.sin((t + p.phase) * cad)) * 0.075 * w;
      p.model.position.set(p.pos.x, this.heightFn(p.pos.x, p.pos.y) + bob, p.pos.y);
      p.model.rotation.y = Math.atan2(dx, dz);
      p.model.rotation.x = 0.045 * w + (p.role === 'elder' ? 0.06 : 0);   // 前傾；老人家再駝一點
      if (!far) animateCharacter(p.model, t + p.phase, animSpeed);
    }

    // 兩回合：推開彼此 → 推出牆壁 → 再推一次。
    // 只做一回合的話，「推出牆壁」那一步可能把人推進旁邊的人身上，
    // 兩種穿模輪流出現。第二回合把互推的殘量收掉，牆壁那一步最後生效
    // ——寧可兩個人擦肩，也不要有人半個身體在牆裡。
    this._separate();
    this._unstick();
    this._separate();
    this._unstick();

    // 推完之後才把模型的水平位置補上（y 留給上面算好的彈跳）
    for (const p of this.people) {
      p.model.position.x = p.pos.x;
      p.model.position.z = p.pos.y;
    }
  }

  /**
   * 互相推開 —— 路人不該從彼此身上穿過去。
   *
   * 大家走在同一組路點之間，遲早會有兩個人同時佔住同一段路（迎面、
   * 或後面的追上前面的）。沒有這一步的話兩個人會直接重疊成一個
   * 四手四腳的東西，是最顯眼的穿模。
   *
   * 做法是最便宜的那種：位置直接對推，不動速度也不做真的物理 ——
   * 路人只要「看起來會讓路」就夠了。空間格切成 R 見方的桶，
   * 只比對相鄰桶，六十幾個人也不會變成 O(n²)。
   */
  _separate() {
    const R = 0.62;                       // 兩個人的肩寬和
    const buckets = new Map();
    const key = (x, z) => `${Math.floor(x / R)},${Math.floor(z / R)}`;
    for (const p of this.people) {
      const k = key(p.pos.x, p.pos.y);
      let b = buckets.get(k);
      if (!b) buckets.set(k, (b = []));
      b.push(p);
    }

    for (const p of this.people) {
      const bx = Math.floor(p.pos.x / R), bz = Math.floor(p.pos.y / R);
      for (let ox = -1; ox <= 1; ox++) {
        for (let oz = -1; oz <= 1; oz++) {
          const b = buckets.get(`${bx + ox},${bz + oz}`);
          if (!b) continue;
          for (const q of b) {
            if (q === p) continue;
            let dx = q.pos.x - p.pos.x, dz = q.pos.y - p.pos.y;
            let d = Math.hypot(dx, dz);
            if (d >= R) continue;
            if (d < 1e-4) {              // 完全重合：隨便挑個方向推開
              dx = Math.cos(p.phase); dz = Math.sin(p.phase); d = 1;
            }
            // 各退一半，總和剛好把兩人分到 R
            const push = (R - d) * 0.5;
            p.pos.x -= (dx / d) * push;
            p.pos.y -= (dz / d) * push;
            q.pos.x += (dx / d) * push;
            q.pos.y += (dz / d) * push;
          }
        }
      }
    }

  }

  /**
   * 把插在建築裡的路人推出來。
   *
   * 路點圖是手繪的，總有幾條連線從屋角或神像基座切過去；再加上上面
   * 的互推可能把人擠進牆裡。玩家看到的就是半個身體埋在牆中 —— 這是
   * 最刺眼的穿模。
   *
   * 推的方向取「離哪一面牆最近就往哪一面推」（矩形）或徑向（柱）：
   * 沿最短路徑出來，人不會被彈飛到街的另一邊。
   */
  /**
   * 往前探 PROBE 公尺，撞到障礙就沿切線偏轉。
   *
   * 只挑「最擋路的那一個」處理 —— 同時對三個障礙求平均方向的話，
   * 夾在兩棟房子中間時兩邊的偏轉會互相抵銷，人就直直撞上去了。
   *
   * @returns {{x:number, z:number}} 正規化過的行進方向
   */
  _avoid(px, pz, ux, uz) {
    const PROBE = 2.0, PAD = 0.55;      // PAD 比 _unstick 的 0.3 大：提早繞開，而不是貼到牆才推
    const tx = px + ux * PROBE, tz = pz + uz * PROBE;
    let worst = null, worstPen = 0;
    for (const c of this.colliders) {
      let cx, cz, pen;
      if (c.hw != null) {
        // 方盒：取探測點在盒面上的最近點，反推穿透深度
        const nx = Math.max(c.x - c.hw, Math.min(tx, c.x + c.hw));
        const nz = Math.max(c.z - c.hd, Math.min(tz, c.z + c.hd));
        const d = Math.hypot(tx - nx, tz - nz);
        if (d >= PAD) continue;
        pen = PAD - d; cx = c.x; cz = c.z;
      } else {
        const d = Math.hypot(tx - c.x, tz - c.z);
        if (d >= c.r + PAD) continue;
        pen = c.r + PAD - d; cx = c.x; cz = c.z;
      }
      if (pen > worstPen) { worstPen = pen; worst = { cx, cz }; }
    }
    if (!worst) return { x: ux, z: uz };

    // 切線：障礙中心指向自己的方向轉 90 度。兩個切線方向挑跟原方向夾角
    // 較小的那邊繞 —— 挑錯邊會整個人往回走。
    let ax = px - worst.cx, az = pz - worst.cz;
    const al = Math.hypot(ax, az) || 1;
    ax /= al; az /= al;
    const t1x = -az, t1z = ax;
    const dot = t1x * ux + t1z * uz;
    const sgn = dot >= 0 ? 1 : -1;
    // 穿透越深轉得越多；乘 1.6 讓它真的繞得開，只加一點點會擦著牆走
    const k = Math.min(1, worstPen * 1.6);
    let rx = ux + sgn * t1x * k, rz = uz + sgn * t1z * k;
    const rl = Math.hypot(rx, rz) || 1;
    return { x: rx / rl, z: rz / rl };
  }

  _unstick() {
    const PAD = 0.3;                 // 身體半徑：貼著牆走可以，插進去不行
    for (const p of this.people) {
      for (const c of this.colliders) {
        if (c.hw != null) {
          const dx = p.pos.x - c.x, dz = p.pos.y - c.z;
          const ox = c.hw + PAD - Math.abs(dx);
          const oz = c.hd + PAD - Math.abs(dz);
          if (ox <= 0 || oz <= 0) continue;          // 沒有重疊
          // 推出重疊較淺的那一軸
          if (ox < oz) p.pos.x = c.x + Math.sign(dx || 1) * (c.hw + PAD);
          else p.pos.y = c.z + Math.sign(dz || 1) * (c.hd + PAD);
        } else {
          const dx = p.pos.x - c.x, dz = p.pos.y - c.z;
          const d = Math.hypot(dx, dz);
          const need = c.r + PAD;
          if (d >= need) continue;
          if (d < 1e-4) { p.pos.x = c.x + need; continue; }
          p.pos.x = c.x + (dx / d) * need;
          p.pos.y = c.z + (dz / d) * need;
        }
      }
    }
  }

  /**
   * 依距離挑細節層級 —— 跟 NPCManager 同一組門檻（config.js 的 CHAR_LOD）。
   * @returns {boolean} 是否已切到遠景單網格（呼叫端據此跳過動畫）
   */
  _lod(p, playerPos) {
    if (!playerPos) return false;
    const d = Math.hypot(p.pos.x - playerPos.x, p.pos.y - playerPos.z);

    const wantOutline = d < CHAR_LOD.outline;
    if (p.outlineOn !== wantOutline) {
      p.outlineOn = wantOutline;
      for (const o of p.outlines) o.visible = wantOutline;
    }

    return setCharacterFar(p.model, d >= CHAR_LOD.far);
  }
}
