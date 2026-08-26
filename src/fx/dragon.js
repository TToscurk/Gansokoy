// 日暈之龍 —— 拾壹之型與拾參之型專用的火龍。
//
// 做法刻意不用模型：龍身是一條「十字緞帶」（每一節同時吐出直立與水平
// 兩片四邊形），從任何角度看都有體積感，成本卻只有兩條 triangle strip。
// 龍身沿著攻擊方向前進，同時左右上下蛇行；頭大尾細、頭橘尾藍。
//
// 一次只會有一條龍（招式間隔比龍的壽命長），所以幾何體重複使用不另配置。

import * as THREE from 'three';
import { BREATH_CORE, BREATH_EDGE } from '../combat/forms.js';

const SEG = 18;            // 龍身分節
const BODY = 7.0;          // 龍身全長（公尺）
const RANGE = 15;          // 頭部總飛行距離
const R0 = 0.95;           // 龍身最粗處半徑

const _CORE = new THREE.Color(BREATH_CORE);
const _EDGE = new THREE.Color(BREATH_EDGE);
const _WHITE = new THREE.Color(0xfff2d0);

const _fwd = new THREE.Vector3();
const _side = new THREE.Vector3();
const _c = new THREE.Vector3();

export class FireDragon {
  constructor(scene) {
    this.scene = scene;
    this.on = false;
    this.life = 0;
    this.ttl = 0.95;
    this.origin = new THREE.Vector3();
    this.yaw = 0;
    this.scale = 1;
    this.headPos = new THREE.Vector3();

    // 每節 4 個頂點：上、下、左、右（兩片交叉的緞帶共用）
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(SEG * 12), 3));
    g.setAttribute('color', new THREE.BufferAttribute(new Float32Array(SEG * 12), 3));
    const idx = [];
    for (let i = 0; i < SEG - 1; i++) {
      const a = i * 4, b = (i + 1) * 4;
      idx.push(a, a + 1, b, a + 1, b + 1, b);        // 直立那片
      idx.push(a + 2, a + 3, b + 2, a + 3, b + 3, b + 2); // 水平那片
    }
    g.setIndex(idx);
    this.geo = g;

    const mat = new THREE.MeshBasicMaterial({
      vertexColors: true, transparent: true,
      blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
    });
    this.mesh = new THREE.Mesh(g, mat);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 5;

    // 龍頭：一個朝前的四角錐，比龍身亮
    const head = new THREE.ConeGeometry(0.78, 1.85, 4);
    head.rotateX(-Math.PI / 2);                      // 錐尖朝 +Z
    this.head = new THREE.Mesh(head, new THREE.MeshBasicMaterial({
      color: 0xffd08a, transparent: true,
      blending: THREE.AdditiveBlending, depthWrite: false,
    }));
    this.head.frustumCulled = false;
    this.head.renderOrder = 5;
  }

  /** 放一條龍。yaw = 玩家朝向（模型正面是 +Z）。 */
  spawn(pos, yaw, opts = {}) {
    this.origin.set(pos.x, pos.y + 1.15, pos.z);
    this.yaw = yaw;
    this.scale = opts.scale ?? 1;
    this.ttl = opts.ttl ?? 0.95;
    this.life = 0;
    // 先對齊出生點：spawn 到第一次 update 之間若有人讀 headPos，
    // 拿到的會是上一條龍的殘值或初始的 (0,0,0)
    this.headPos.copy(this.origin);
    if (!this.on) {
      this.scene.add(this.mesh);
      this.scene.add(this.head);
      this.on = true;
    }
  }

  /** @param embers 有給的話，龍頭會沿路噴火星 */
  update(dt, embers) {
    if (!this.on) return;
    this.life += dt;
    const t = this.life / this.ttl;
    if (t >= 1) {
      this.scene.remove(this.mesh);
      this.scene.remove(this.head);
      this.on = false;
      return;
    }

    // 前進：出場快、尾段慢下來（easeOutCubic）
    const ease = 1 - (1 - t) * (1 - t) * (1 - t);
    const headD = ease * RANGE * this.scale;
    const fade = t < 0.72 ? 1 : 1 - (t - 0.72) / 0.28;

    _fwd.set(Math.sin(this.yaw), 0, Math.cos(this.yaw));
    _side.set(_fwd.z, 0, -_fwd.x);                    // 水平法線

    const pos = this.geo.attributes.position.array;
    const col = this.geo.attributes.color.array;

    for (let i = 0; i < SEG; i++) {
      const s = i / (SEG - 1);                        // 0 = 頭、1 = 尾
      // 尾巴還沒離開身體時要縮在原點，不然一出招就是一整條浮在半空
      const d = Math.max(0, headD - s * BODY * this.scale);

      // 蛇行：越靠尾巴擺幅越大，整條隨時間推進
      const ph = s * 5.6 - this.life * 13;
      const amp = (0.25 + s * 1.15) * this.scale;
      const lat = Math.sin(ph) * amp;
      const vert = Math.cos(ph * 0.8 + 0.7) * amp * 0.55 + s * 0.35;

      _c.copy(this.origin)
        .addScaledVector(_fwd, d)
        .addScaledVector(_side, lat);
      _c.y += vert;

      // 頭粗尾細，頭部附近再鼓一點
      const r = R0 * this.scale * Math.pow(1 - s, 0.55) * (1 + 0.35 * Math.exp(-s * 9));

      const p = i * 12;
      pos[p]      = _c.x;             pos[p + 1]  = _c.y + r; pos[p + 2]  = _c.z;
      pos[p + 3]  = _c.x;             pos[p + 4]  = _c.y - r; pos[p + 5]  = _c.z;
      pos[p + 6]  = _c.x + _side.x * r; pos[p + 7] = _c.y;    pos[p + 8]  = _c.z + _side.z * r;
      pos[p + 9]  = _c.x - _side.x * r; pos[p + 10] = _c.y;   pos[p + 11] = _c.z - _side.z * r;

      // 顏色：頭是近白的橘 → 中段日輪橘 → 尾巴氣流藍，整條再乘上淡出
      const k = fade * (1 - s * 0.15);
      let r0, g0, b0;
      if (s < 0.22) {
        const u = s / 0.22;
        r0 = _WHITE.r + (_CORE.r - _WHITE.r) * u;
        g0 = _WHITE.g + (_CORE.g - _WHITE.g) * u;
        b0 = _WHITE.b + (_CORE.b - _WHITE.b) * u;
      } else {
        const u = (s - 0.22) / 0.78;
        r0 = _CORE.r + (_EDGE.r - _CORE.r) * u;
        g0 = _CORE.g + (_EDGE.g - _CORE.g) * u;
        b0 = _CORE.b + (_EDGE.b - _CORE.b) * u;
      }
      for (let v = 0; v < 4; v++) {
        const q = p + v * 3;
        col[q] = r0 * k; col[q + 1] = g0 * k; col[q + 2] = b0 * k;
      }

      if (i === 0) this.headPos.copy(_c);
    }

    this.geo.attributes.position.needsUpdate = true;
    this.geo.attributes.color.needsUpdate = true;

    // 龍頭跟著第一節，朝著前進方向
    this.head.position.copy(this.headPos);
    this.head.rotation.y = this.yaw;
    this.head.scale.setScalar(this.scale * (0.75 + 0.25 * Math.sin(this.life * 22)));
    this.head.material.opacity = fade;

    // 沿路噴火星
    if (embers && fade > 0.2) {
      const n = 3;
      for (let i = 0; i < n; i++) {
        embers.spawn(this.headPos, {
          x: (Math.random() - 0.5) * 4 - _fwd.x * 1.5,
          y: 1.2 + Math.random() * 2.6,
          z: (Math.random() - 0.5) * 4 - _fwd.z * 1.5,
        }, { color: i === 0 ? 0x9ec4ff : 0xffb050, size: 0.3, ttl: 0.55, drag: 1.1 });
      }
    }
  }
}
