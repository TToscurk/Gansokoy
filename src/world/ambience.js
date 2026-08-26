// 環境生命（地圖品質升級書・升級 7 第 2 點）。
//
// 「像關卡不像地方」的一大來源是：所有東西都不動。一張圖就算佈置得再滿，
// 靜止不動就是佈景。這裡收四種便宜的 idle 動態，每張圖挑兩種以上掛上去：
//
//   smoke()   炊煙 —— 有人住的證據
//   birds()   飛鳥剪影 —— 天空不再是一張貼圖
//   drift()   落葉／花瓣 —— 空氣在動
//   banner()  晾曬的布幔 —— 風在吹
//
// 全部走 InstancedMesh 或單一網格，加起來一張圖多不到十個 draw call。
// 共通做法：粒子不生不滅，**循環重用**固定數量的 instance ——
// 每幀 new 一批再丟掉會讓 GC 在遊玩中抽動。
//
// 用法：
//   const amb = new Ambience(world);
//   amb.smoke(x, y, z);
//   amb.birds({ cx: 0, cz: 0, r: 90, y: 46 });
//   core.onUpdate((dt, rawDt, t) => amb.update(dt, t));

import * as THREE from 'three';

/** 決定性亂數 —— 每次重整的初始分布要一樣，不然截圖比對沒有意義 */
function rng(seed = 1) {
  let s = (seed >>> 0) || 1;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0), s / 4294967296);
}

export class Ambience {
  /**
   * @param {THREE.Object3D} world 掛載的父節點
   * @param {number} [seed=7]
   */
  constructor(world, seed = 7) {
    this.world = world;
    this.rand = rng(seed);
    this._parts = [];
  }

  /** 每幀呼叫。@param dt 秒 @param t 累積時間（給週期動畫） */
  update(dt, t) {
    for (const p of this._parts) p.update(dt, t);
  }

  /* ────────────────────────────────────────────────── 炊煙 ── */
  /**
   * 從一點升起的煙。粒子往上飄、邊飄邊變大變淡，到頂重新回到底部。
   *
   * @param {number} x @param {number} y @param {number} z 煙囪口
   * @param {object} [o]
   * @param {number} [o.count=14]  粒子數
   * @param {number} [o.rise=5.2]  升到多高就重來
   * @param {number} [o.speed=0.55] 上升速度（公尺/秒）
   * @param {number} [o.drift=0.5] 水平飄移
   * @param {number|string} [o.color=0xd8d4cc]
   */
  smoke(x, y, z, {
    count = 14, rise = 5.2, speed = 0.55, drift = 0.5, color = 0xd8d4cc,
  } = {}) {
    const geo = new THREE.PlaneGeometry(1, 1);
    const mat = new THREE.MeshBasicMaterial({
      color, transparent: true, opacity: 0.5, depthWrite: false, fog: true,
    });
    const im = new THREE.InstancedMesh(geo, mat, count);
    im.userData.noMerge = true;
    im.frustumCulled = false;          // 粒子每幀都在動，包圍盒沒有意義
    this.world.add(im);

    // 每顆粒子錯開起始高度，不然整串同時出生同時消失，像在打嗝
    const ps = Array.from({ length: count }, (_, i) => ({
      p: i / count, sway: this.rand() * 6.28, spin: (this.rand() - 0.5) * 0.8,
    }));
    const m4 = new THREE.Matrix4(), q = new THREE.Quaternion();
    const e = new THREE.Euler(), v = new THREE.Vector3(), sc = new THREE.Vector3();

    this._parts.push({
      update: (dt, t) => {
        for (let i = 0; i < count; i++) {
          const s = ps[i];
          s.p += (speed / rise) * dt;
          if (s.p > 1) s.p -= 1;
          const h = s.p * rise;
          // 越高越大越淡 —— 煙散開是體積擴散，不是原地淡出
          const size = 0.35 + s.p * 1.5;
          e.set(0, 0, s.spin * t + s.sway);
          q.setFromEuler(e);
          sc.set(size, size, size);
          v.set(x + Math.sin(t * 0.6 + s.sway) * drift * s.p, y + h,
            z + Math.cos(t * 0.45 + s.sway) * drift * s.p);
          m4.compose(v, q, sc);
          im.setMatrixAt(i, m4);
        }
        im.instanceMatrix.needsUpdate = true;
        // 整串的不透明度用最舊那顆的進度帶 —— 逐顆改要開 instanceColor，
        // 為了煙不值得
        mat.opacity = 0.5;
      },
    });
    return im;
  }

  /* ──────────────────────────────────────────── 飛鳥剪影 ── */
  /**
   * 一小群鳥繞著圈飛。剪影就好 —— 這是天空的動態，不是主角。
   *
   * @param {object} o
   * @param {number} o.cx @param {number} o.cz 繞行中心
   * @param {number} [o.r=80] 半徑
   * @param {number} [o.y=42] 高度
   * @param {number} [o.count=5]
   * @param {number} [o.speed=0.06] 角速度（rad/s）
   * @param {number|string} [o.color=0x2a2f38]
   */
  birds({ cx = 0, cz = 0, r = 80, y = 42, count = 5, speed = 0.06, color = 0x2a2f38 } = {}) {
    // 一隻鳥＝兩片三角形的 V 字。側面看是一條線，正好是剪影該有的樣子
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute([
      0, 0, 0, -1, 0.42, -0.3, -0.9, 0, 0.1,
      0, 0, 0, 1, 0.42, -0.3, 0.9, 0, 0.1,
    ], 3));
    g.computeVertexNormals();
    const mat = new THREE.MeshBasicMaterial({
      color, side: THREE.DoubleSide, fog: true, transparent: true, opacity: 0.75,
    });
    const im = new THREE.InstancedMesh(g, mat, count);
    im.userData.noMerge = true;
    im.frustumCulled = false;
    this.world.add(im);

    const bs = Array.from({ length: count }, () => ({
      a: this.rand() * 6.28,
      rr: r * (0.75 + this.rand() * 0.5),
      yy: y + (this.rand() - 0.5) * 10,
      flap: this.rand() * 6.28,
      sz: 0.9 + this.rand() * 0.7,
    }));
    const m4 = new THREE.Matrix4(), q = new THREE.Quaternion();
    const e = new THREE.Euler(), v = new THREE.Vector3(), sc = new THREE.Vector3();

    this._parts.push({
      update: (dt, t) => {
        for (let i = 0; i < count; i++) {
          const b = bs[i];
          b.a += speed * dt;
          const px = cx + Math.cos(b.a) * b.rr;
          const pz = cz + Math.sin(b.a) * b.rr;
          // 拍翅：用 Y 縮放做，比真的動頂點便宜太多
          const flap = 0.55 + Math.abs(Math.sin(t * 3.2 + b.flap)) * 0.75;
          e.set(0, -b.a + Math.PI / 2, 0);
          q.setFromEuler(e);
          sc.set(b.sz, b.sz * flap, b.sz);
          m4.compose(v.set(px, b.yy + Math.sin(t * 0.5 + b.flap) * 1.2, pz), q, sc);
          im.setMatrixAt(i, m4);
        }
        im.instanceMatrix.needsUpdate = true;
      },
    });
    return im;
  }

  /* ─────────────────────────────────────── 落葉／花瓣 ── */
  /**
   * 在一個範圍內緩緩飄落的碎片。落到底就回到頂端 —— 循環重用。
   *
   * @param {object} o
   * @param {number} o.hx @param {number} o.hz 範圍半徑（以 cx,cz 為心）
   * @param {number} [o.cx=0] @param {number} [o.cz=0]
   * @param {number} [o.top=14] 出生高度
   * @param {(x:number,z:number)=>number} [o.groundAt] 地面高度（不給就用 0）
   * @param {number} [o.count=90]
   * @param {number} [o.fall=0.9] 落速
   * @param {number|string} [o.color=0xc8b46a]
   * @param {number} [o.size=0.13]
   */
  drift({
    hx = 40, hz = 40, cx = 0, cz = 0, top = 14, groundAt = null,
    count = 90, fall = 0.9, color = 0xc8b46a, size = 0.13,
  } = {}) {
    const geo = new THREE.PlaneGeometry(size * 2.4, size);
    const mat = new THREE.MeshStandardMaterial({
      color, roughness: 1, side: THREE.DoubleSide, transparent: true, opacity: 0.9,
    });
    const im = new THREE.InstancedMesh(geo, mat, count);
    im.userData.noMerge = true;
    im.frustumCulled = false;
    this.world.add(im);

    const ps = Array.from({ length: count }, () => {
      const x = cx + (this.rand() * 2 - 1) * hx;
      const z = cz + (this.rand() * 2 - 1) * hz;
      return {
        x, z, y: (groundAt ? groundAt(x, z) : 0) + this.rand() * top,
        sway: this.rand() * 6.28, spin: (this.rand() - 0.5) * 2.2,
        vy: fall * (0.6 + this.rand() * 0.8),
      };
    });
    const m4 = new THREE.Matrix4(), q = new THREE.Quaternion();
    const e = new THREE.Euler(), v = new THREE.Vector3(), sc = new THREE.Vector3();
    sc.set(1, 1, 1);

    this._parts.push({
      update: (dt, t) => {
        for (let i = 0; i < count; i++) {
          const p = ps[i];
          p.y -= p.vy * dt;
          const floor = groundAt ? groundAt(p.x, p.z) : 0;
          if (p.y < floor) {
            // 回到頂端，同時換一個水平位置 —— 原地重生會排出一根根柱子
            p.x = cx + (this.rand() * 2 - 1) * hx;
            p.z = cz + (this.rand() * 2 - 1) * hz;
            p.y = (groundAt ? groundAt(p.x, p.z) : 0) + top;
          }
          // 飄：落葉不是直直掉下來的
          const sx = Math.sin(t * 0.8 + p.sway) * 0.5;
          const sz = Math.cos(t * 0.6 + p.sway) * 0.5;
          e.set(t * p.spin, p.sway + t * 0.3, t * p.spin * 0.7);
          q.setFromEuler(e);
          m4.compose(v.set(p.x + sx, p.y, p.z + sz), q, sc);
          im.setMatrixAt(i, m4);
        }
        im.instanceMatrix.needsUpdate = true;
      },
    });
    return im;
  }

  /* ────────────────────────────────────────── 晾曬的布幔 ── */
  /**
   * 掛著的布，被風吹得起伏。逐頂點做正弦波 —— 一塊布才幾十個頂點，
   * 比用骨骼或物理便宜得多，而且看起來一樣。
   *
   * @param {number} x @param {number} y @param {number} z 布的中心
   * @param {object} [o]
   * @param {number} [o.w=1.6] @param {number} [o.h=1.1]
   * @param {number} [o.rot=0] 繞 Y 的朝向
   * @param {number|string} [o.color=0xc9503c]
   * @param {number} [o.amp=0.12] 起伏幅度
   */
  banner(x, y, z, { w = 1.6, h = 1.1, rot = 0, color = 0xc9503c, amp = 0.12 } = {}) {
    const geo = new THREE.PlaneGeometry(w, h, 8, 4);
    const mat = new THREE.MeshStandardMaterial({
      color, roughness: 0.95, side: THREE.DoubleSide,
    });
    const mesh = new THREE.Mesh(geo, mat);
    mesh.position.set(x, y, z);
    mesh.rotation.y = rot;
    mesh.castShadow = true;
    mesh.userData.noMerge = true;      // 頂點每幀在動，合併進靜態批次就不會動了
    this.world.add(mesh);

    const pos = geo.attributes.position;
    const base = Float32Array.from(pos.array);
    const phase = this.rand() * 6.28;

    this._parts.push({
      update: (dt, t) => {
        for (let i = 0; i < pos.count; i++) {
          const bx = base[i * 3], by = base[i * 3 + 1];
          // 上緣固定（掛著），越往下擺幅越大
          const hang = (h / 2 - by) / h;
          pos.setZ(i, Math.sin(t * 1.9 + bx * 2.4 + phase) * amp * hang);
        }
        pos.needsUpdate = true;
        geo.computeVertexNormals();
      },
    });
    return mesh;
  }
}
