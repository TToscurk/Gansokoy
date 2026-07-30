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
import { buildCharacter, animateCharacter } from './model.js';

// 村民的衣著配色（樸素的和服色系，跟主要角色的鮮豔配色區隔開）
const HAIR = [0x2a2118, 0x3a2c20, 0x4a3a28, 0x1e1a18, 0x5a4632];
const OUTFIT = [
  0x6a6250, 0x7a6a52, 0x585f68, 0x6e5a4a, 0x4a5560,
  0x8a7a5e, 0x5c6650, 0x74604e, 0x3f4a52, 0x7d6a6a,
];
const ACCENT = [0x9a5a4a, 0x4a6a7a, 0x7a6a3a, 0x6a4a5a, 0x3a5a4a];
const SKIN = [0xf0cead, 0xe8c4a4, 0xdcb896, 0xf4d8bc];
const HAIRSTYLE = ['short', 'long', 'longTied', 'bob', 'longStraight'];

const pick = (arr, r) => arr[(r * arr.length) | 0];

/** 決定性亂數：同一個 index 每次重整都長一樣，畫面不會每次刷新都跳動 */
function rnd(seed) {
  const v = Math.sin(seed * 91.7 + 43.3) * 37219.1;
  return v - Math.floor(v);
}

function villagerSpec(i) {
  const r1 = rnd(i * 3.1), r2 = rnd(i * 7.7), r3 = rnd(i * 13.3), r4 = rnd(i * 5.9);
  const outfit = pick(OUTFIT, r2);
  return {
    id: `villager${i}`,
    hair: pick(HAIRSTYLE, r1),
    hat: 'none', wings: 'none', prop: 'none', float: false,
    scale: 0.94 + r4 * 0.16,
    palette: {
      hair: pick(HAIR, r1),
      outfit, outfit2: outfit,
      accent: pick(ACCENT, r3),
      legs: 0xe8e0d0, shoes: 0x4a3a2c,
      eyes: 0x4a3a30, skin: pick(SKIN, r4),
    },
  };
}

export class VillagerCrowd {
  /**
   * @param {THREE.Scene} scene
   * @param {(x:number,z:number)=>number} heightFn
   * @param {object} graph 路點圖 { nodes:[[x,z],...], links:[[a,b],...] }
   * @param {number} [count=22]
   */
  constructor(scene, heightFn, graph, count = 22) {
    this.scene = scene;
    this.heightFn = heightFn;
    this.nodes = graph.nodes.map(([x, z]) => new THREE.Vector2(x, z));
    // 相鄰表：雙向
    this.adj = this.nodes.map(() => []);
    for (const [a, b] of graph.links) { this.adj[a].push(b); this.adj[b].push(a); }

    this.root = new THREE.Group();
    scene.add(this.root);
    this.visible = true;
    this.people = [];

    for (let i = 0; i < count; i++) {
      const model = buildCharacter(villagerSpec(i));
      const outlines = [];
      model.traverse(o => { if (o.name === 'outline') outlines.push(o); });
      this.root.add(model);

      // 起點：隨機一個路點，目標：它的隨機鄰居
      const from = (rnd(i * 2.3) * this.nodes.length) | 0;
      const to = this._nextFrom(from, -1, rnd(i * 4.1));
      const p = this.nodes[from].clone();
      this.people.push({
        model, outlines, from, to,
        pos: p,
        speed: 1.5 + rnd(i * 8.8) * 1.5,
        phase: rnd(i * 6.4) * 10,
        idle: rnd(i * 9.2) * 6,        // 一開始各自錯開，不會整群同步
        outlineOn: null,
      });
    }
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

    for (const p of this.people) {
      // 停下來發呆
      if (p.idle > 0) {
        p.idle -= dt;
        p.model.position.y = this.heightFn(p.pos.x, p.pos.y);
        animateCharacter(p.model, t + p.phase, 0);
        this._cull(p, playerPos);
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

      const step = Math.min(d, p.speed * dt);
      p.pos.x += (dx / d) * step;
      p.pos.y += (dz / d) * step;

      p.model.position.set(p.pos.x, this.heightFn(p.pos.x, p.pos.y), p.pos.y);
      p.model.rotation.y = Math.atan2(dx, dz);
      animateCharacter(p.model, t + p.phase, p.speed);
      this._cull(p, playerPos);
    }
  }

  /** 遠處關描邊 —— 跟 NPCManager 同一套省 draw call 的做法 */
  _cull(p, playerPos) {
    if (!playerPos) return;
    const d = Math.hypot(p.pos.x - playerPos.x, p.pos.y - playerPos.z);
    const want = d < 18;
    if (p.outlineOn !== want) {
      p.outlineOn = want;
      for (const o of p.outlines) o.visible = want;
    }
  }
}
