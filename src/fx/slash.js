// 斬擊特效池 —— 橘藍雙色的新月劍氣。
//
// 視覺分層（同一招疊三片，各有各的壽命）：
//   主弧  —— 頂點色扇形：內緣橘、外緣藍，0.6 倍徑長到全徑，快閃
//   殘影  —— 同色調但更淡更藍的一片，慢 1.6 倍消退，拖出「軌跡」
//   火花  —— 命中點的小光斑，向外飛散
// 全部 additive + depthWrite:false，bloom 會自己把亮部推成光暈。
//
// 池化：mesh 物件重複用，幾何體每招重建（40 個頂點上下，比維護
// drawRange 邏輯便宜得多）。連打一秒三招也不過三份小幾何。

import * as THREE from 'three';
import { BREATH_CORE, BREATH_EDGE } from '../combat/forms.js';
import { EmberField } from './embers.js';
import { FireDragon } from './dragon.js';

const MAX_SLASH = 10;

// --- 刀光（跟著刀身跑的軌跡帶） ---
const TRAIL_N = 26;          // 環狀緩衝的取樣點數
const TRAIL_TTL = 0.30;      // 單一取樣點的壽命（秒）＝ 尾巴長度。
                             // 太短的話旋轉類招式只看得到 1/4 圈
const TRAIL_MIN_STEP = 0.06; // 刀尖每幀移動不到這個距離就不採樣 ——
                             // 起手/收招是慢動作，不該拖出刀光

const _CORE = new THREE.Color(BREATH_CORE);
const _EDGE = new THREE.Color(BREATH_EDGE);
const _v = new THREE.Vector3();
const _p = new THREE.Vector3();

/** 扇形環帶幾何：y=0 平面上、面朝 dir 張開 arc 角、內徑 r0 外徑 r1。
 *  頂點色內緣 core、外緣 edge，弧的兩端 alpha 漸淡（用色變暗代替——
 *  additive 混合下「變黑」就是變透明）。k = 整體亮度（殘影層用來壓暗）。 */
function sectorGeo(arc, r0, r1, core, edge, segs = 26, k = 1) {
  const pos = [], col = [], idx = [];
  const c = new THREE.Color(core).multiplyScalar(k);
  const e = new THREE.Color(edge).multiplyScalar(k);
  for (let i = 0; i <= segs; i++) {
    const t = i / segs;
    const a = (t - 0.5) * arc;
    const ca = Math.cos(a), sa = Math.sin(a);
    pos.push(ca * r0, 0, sa * r0, ca * r1, 0, sa * r1);
    // 弧端漸暗（additive 下=淡出）
    const endFade = Math.sin(Math.PI * t) ** 0.7;
    col.push(c.r * endFade, c.g * endFade, c.b * endFade,
             e.r * endFade, e.g * endFade, e.b * endFade);
    if (i < segs) {
      const b = i * 2;
      idx.push(b, b + 1, b + 2, b + 1, b + 3, b + 2);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  g.setIndex(idx);
  return g;
}

export class SlashFX {
  constructor(scene) {
    this.scene = scene;
    this.slashes = [];   // {mesh, life, ttl, grow, rise, spin}

    this._slashMat = new THREE.MeshBasicMaterial({
      vertexColors: true, transparent: true, opacity: 1,
      blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
    });

    // 火星與火龍。火星全部塞進一個 Points（原本一顆一個 Mesh，
    // 40 顆就是 40 個 draw call），火龍只在龍形/終結技出場。
    this.embers = new EmberField(scene);
    this.dragon = new FireDragon(scene);

    this._pool = [];

    // 刀光：固定大小的環狀緩衝，執行時零配置
    this._trail = {
      buf: Array.from({ length: TRAIL_N }, () => ({
        a: new THREE.Vector3(), b: new THREE.Vector3(), age: 1e9,
      })),
      head: TRAIL_N - 1,
      started: false,
      boost: 1,
      mesh: null,
      on: false,
    };
  }

  _trailMesh() {
    const t = this._trail;
    if (!t.mesh) {
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(TRAIL_N * 6), 3));
      g.setAttribute('color', new THREE.BufferAttribute(new Float32Array(TRAIL_N * 6), 3));
      const idx = [];
      for (let i = 0; i < TRAIL_N - 1; i++) {
        const b = i * 2;
        idx.push(b, b + 1, b + 2, b + 1, b + 3, b + 2);
      }
      g.setIndex(idx);
      t.mesh = new THREE.Mesh(g, this._slashMat);
      t.mesh.frustumCulled = false;
      t.mesh.renderOrder = 5;
    }
    return t.mesh;
  }

  /** 開一道新刀光（出招瞬間呼叫）。緩衝整個重置，才不會跟上一招連成一條。
   *  pos/yaw 只有火龍需要 —— 龍形與終結技才會放。 */
  beginTrail(form, pos, yaw) {
    const t = this._trail;
    for (const s of t.buf) s.age = 1e9;
    t.started = false;
    t.boost = form.finisher ? 1.55 : form.heavy || form.dragon ? 1.25 : 1;
    t.ember = form.finisher ? 4 : form.heavy || form.dragon ? 3 : 2;   // 每個取樣點甩幾顆
    if (!t.on) { this.scene.add(this._trailMesh()); t.on = true; }

    if (pos && (form.dragon || form.finisher)) {
      this.dragon.spawn(pos, yaw, {
        scale: form.finisher ? 1.35 : 1,
        ttl: form.finisher ? 1.15 : 0.95,
      });
      // 出龍的瞬間腳下炸一圈，重量感從這裡來
      this.embers.burst({ x: pos.x, y: pos.y + 0.25, z: pos.z },
        form.finisher ? 26 : 16,
        { color: 0xffa040, size: 0.34, speed: 7, up: 4, ttl: 0.6 });
    }
  }

  /**
   * 餵一幀的刀身位置。a = 刀身內側點、b = 刀尖（世界座標）。
   * 刀尖沒動夠遠就不採樣 —— 這樣起手與收招的慢動作不會拖出刀光，
   * 不必在招式資料裡標「哪一段才是斬擊」。
   */
  traceBlade(a, b) {
    const t = this._trail;
    if (!t.on) return;

    if (!t.started) {
      // 開頭把整條緩衝壓到同一點：否則第一格會跟上一招的殘留位置連成一道長條
      for (const s of t.buf) { s.a.copy(a); s.b.copy(b); s.age = 1e9; }
      t.started = true;
    } else if (t.buf[t.head].b.distanceTo(b) < TRAIL_MIN_STEP) {
      return;
    }

    const prev = t.buf[t.head];
    t.head = (t.head + 1) % TRAIL_N;
    const s = t.buf[t.head];
    s.a.copy(a); s.b.copy(b); s.age = 0;

    // 刀尖沿路甩出火星：方向取自刀身這一格的位移，所以火星是「被甩出去」
    // 而不是原地噴，揮得越快甩得越遠。
    const n = t.ember || 1;
    for (let i = 0; i < n; i++) {
      _v.subVectors(s.b, prev.b).multiplyScalar(7 + Math.random() * 9);
      this.embers.spawn(
        _p.lerpVectors(s.a, s.b, 0.55 + Math.random() * 0.45),
        {
          x: _v.x + (Math.random() - 0.5) * 2.2,
          y: _v.y + 1.4 + Math.random() * 1.8,
          z: _v.z + (Math.random() - 0.5) * 2.2,
        },
        { color: Math.random() < 0.25 ? 0x8fb8ff : 0xffb452,
          size: 0.2 + Math.random() * 0.16, ttl: 0.34 + Math.random() * 0.28 });
    }
  }

  _updateTrail(dt) {
    const t = this._trail;
    if (!t.on) return;

    let alive = false;
    for (const s of t.buf) {
      s.age += dt;
      if (s.age < TRAIL_TTL) alive = true;
    }
    if (!alive) {                       // 整條淡完就收起來，不佔 draw call
      this.scene.remove(t.mesh);
      t.on = false;
      return;
    }

    const geo = t.mesh.geometry;
    const pos = geo.attributes.position.array;
    const col = geo.attributes.color.array;
    const core = _CORE, edge = _EDGE;

    for (let i = 0; i < TRAIL_N; i++) {
      const s = t.buf[(t.head + 1 + i) % TRAIL_N];   // 由最舊排到最新
      const k = 1 - s.age / TRAIL_TTL;
      // additive 混合下「變黑」就是變透明，所以亮度就是 alpha
      const f = k > 0 ? Math.pow(k, 1.3) * t.boost : 0;
      const p = i * 6, c = i * 6;
      pos[p] = s.a.x; pos[p + 1] = s.a.y; pos[p + 2] = s.a.z;
      pos[p + 3] = s.b.x; pos[p + 4] = s.b.y; pos[p + 5] = s.b.z;
      col[c] = core.r * f; col[c + 1] = core.g * f; col[c + 2] = core.b * f;
      col[c + 3] = edge.r * f; col[c + 4] = edge.g * f; col[c + 5] = edge.b * f;
    }
    geo.attributes.position.needsUpdate = true;
    geo.attributes.color.needsUpdate = true;
  }

  _getMesh() {
    let m = this._pool.pop();
    if (!m) {
      m = new THREE.Mesh(new THREE.BufferGeometry(), this._slashMat);
      m.frustumCulled = false;
      m.renderOrder = 5;
    }
    this.scene.add(m);
    return m;
  }

  /** 放一招斬擊 —— **沒有刀的角色**用的固定扇形（有刀的走 beginTrail/traceBlade，
   *  刀光直接由刀身軌跡生成）。dirYaw = 攻擊朝向（玩家 yaw：前 = (sin, 0, cos)）。
   *  斬弧是「細月牙」不是地毯：帶寬只留外圈 25%，離相機再近也不會
   *  變成蓋住半個螢幕的藍色床單。殘影層亮度壓到 0.4。 */
  slash(pos, dirYaw, form) {
    const { arc, range, dur } = form;
    const thrust = form.thrust;
    // 幾何的 0 弧度朝 +x，玩家 yaw 的前是 (sin,cos)：差 π/2
    const ry = dirYaw - Math.PI / 2;
    const r1 = thrust ? range * 1.15 : range;
    const r0 = thrust ? range * 0.62 : range * 0.74;

    // 主弧：橘核心、藍外緣的細月牙
    const geo = sectorGeo(arc, r0, r1, BREATH_CORE, BREATH_EDGE, thrust ? 10 : 30);
    const mesh = this._getMesh();
    mesh.geometry.dispose();
    mesh.geometry = geo;
    mesh.position.set(pos.x, pos.y + 1.05, pos.z);
    mesh.rotation.set(0, ry, 0);
    this.slashes.push({ mesh, life: 0, ttl: dur, grow: 1, rise: 0.35, spin: form.aoe ? 2.2 : 0 });

    // 殘影層：略小、慢退、整體偏藍且壓暗
    const gGeo = sectorGeo(arc * 0.92, r0 * 0.88, r1 * 0.92,
      BREATH_EDGE, BREATH_EDGE, thrust ? 10 : 26, 0.4);
    const ghost = this._getMesh();
    ghost.geometry.dispose();
    ghost.geometry = gGeo;
    ghost.position.set(pos.x, pos.y + 1.18, pos.z);
    ghost.rotation.set(0, ry, 0);
    this.slashes.push({ mesh: ghost, life: 0, ttl: dur * 1.6, grow: 0.55, rise: 0.8, spin: form.aoe ? -1.4 : 0 });

    // 垂直斬（碧羅之天、火車）：多一片立起來的弧
    if (form.vertical || form.heavy) {
      const vGeo = sectorGeo(Math.PI * 0.85, range * 0.7, range * 0.98,
        BREATH_CORE, BREATH_EDGE, 20, 0.85);
      const vm = this._getMesh();
      vm.geometry.dispose();
      vm.geometry = vGeo;
      vm.position.set(pos.x, pos.y + 0.4, pos.z);
      vm.rotation.set(-Math.PI / 2, 0, 0);
      vm.rotateY(ry);
      this.slashes.push({ mesh: vm, life: 0, ttl: dur * 1.1, grow: 1, rise: 1.6, spin: 0 });
    }
  }

  /** 命中火花：撞擊點噴一叢橘火星，夾幾顆藍的（日之呼吸的配色） */
  hit(pos) {
    const p = { x: pos.x, y: pos.y + 0.9, z: pos.z };
    this.embers.burst(p, 12, { color: 0xffc060, size: 0.24, speed: 6, up: 3.4, ttl: 0.4 });
    this.embers.burst(p, 4, { color: 0x8fb8ff, size: 0.2, speed: 7.5, up: 4, ttl: 0.45 });
  }

  /** 擊殺爆散：更大更慢的一圈，中心補幾顆白熱的 */
  burst(pos) {
    const p = { x: pos.x, y: pos.y + 0.8, z: pos.z };
    this.embers.burst(p, 22, { color: 0xffa848, size: 0.36, speed: 8.5, up: 4.5, ttl: 0.62 });
    this.embers.burst(p, 6, { color: 0xfff0d0, size: 0.44, speed: 3.2, up: 5.5, ttl: 0.5, drag: 2.4 });
  }

  update(dt) {
    this._updateTrail(dt);
    this.dragon.update(dt, this.embers);
    this.embers.update(dt);

    // 斬弧：成長 + 上升 + 消退
    for (let i = this.slashes.length - 1; i >= 0; i--) {
      const s = this.slashes[i];
      s.life += dt;
      const t = s.life / s.ttl;
      if (t >= 1) {
        this.scene.remove(s.mesh);
        this._pool.push(s.mesh);
        this.slashes.splice(i, 1);
        continue;
      }
      const ease = 1 - (1 - t) * (1 - t);   // easeOutQuad
      const sc = 0.55 + ease * 0.5 * s.grow + t * 0.25;
      s.mesh.scale.setScalar(sc);
      s.mesh.position.y += s.rise * dt;
      if (s.spin) s.mesh.rotation.y += s.spin * dt;
      // additive 下用縮放+位置演，透明度交給 ttl 尾端的整體暗化
      s.mesh.material.opacity = 1;
    }

  }
}

// ---------------------------------------------------------------------------
// 出招音效：WebAudio 合成，不需要音檔。
// 破空＝白噪聲過帶通往下滑；火焰＝慢速噪聲過低通竄升再落；重擊再加低頻 thump。
// ---------------------------------------------------------------------------
export class SlashAudio {
  constructor() { this.ctx = null; }

  _ensure() {
    if (!this.ctx) {
      this.ctx = new (window.AudioContext || window.webkitAudioContext)();
      const len = this.ctx.sampleRate * 0.5;
      this._noise = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
      const d = this._noise.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    }
    if (this.ctx.state === 'suspended') this.ctx.resume();
    return this.ctx;
  }

  /**
   * 出招音。form 可以給整個型（讀 heavy/finisher/dragon），
   * 也可以只給一個 boolean（舊呼叫端）。
   * 三層疊起來：破空（高頻帶通下滑）＋ 火焰（低通噪音的轟聲）＋ 重擊的低頻 thump。
   */
  swing(form = false) {
    const heavy = typeof form === 'object'
      ? !!(form.heavy || form.finisher || form.dragon) : !!form;
    const big = typeof form === 'object' && !!(form.finisher || form.dragon);
    try {
      const ctx = this._ensure();
      const t0 = ctx.currentTime;
      const src = ctx.createBufferSource();
      src.buffer = this._noise;
      const bp = ctx.createBiquadFilter();
      bp.type = 'bandpass';
      bp.Q.value = 1.6;
      bp.frequency.setValueAtTime(heavy ? 2600 : 3400, t0);
      bp.frequency.exponentialRampToValueAtTime(heavy ? 500 : 800, t0 + (heavy ? 0.22 : 0.14));
      const g = ctx.createGain();
      g.gain.setValueAtTime(0.0001, t0);
      g.gain.exponentialRampToValueAtTime(heavy ? 0.5 : 0.32, t0 + 0.015);
      g.gain.exponentialRampToValueAtTime(0.0001, t0 + (heavy ? 0.26 : 0.17));
      src.connect(bp).connect(g).connect(ctx.destination);
      src.start(t0);
      src.stop(t0 + 0.3);

      this.fire(big ? 1.5 : heavy ? 1 : 0.62);

      if (heavy) {
        const o = ctx.createOscillator();
        o.type = 'sine';
        o.frequency.setValueAtTime(130, t0);
        o.frequency.exponentialRampToValueAtTime(45, t0 + 0.18);
        const og = ctx.createGain();
        og.gain.setValueAtTime(0.0001, t0);
        og.gain.exponentialRampToValueAtTime(0.4, t0 + 0.012);
        og.gain.exponentialRampToValueAtTime(0.0001, t0 + 0.2);
        o.connect(og).connect(ctx.destination);
        o.start(t0);
        o.stop(t0 + 0.22);
      }
    } catch { /* 音訊被瀏覽器擋就靜音，不影響遊戲 */ }
  }

  /**
   * 火焰聲。同一段白噪聲分兩路：
   *   轟   低通 + 高 Q，截止頻率往上竄再落下 = 火舌捲起來的那聲「呼」
   *   爆裂 帶通掃過中高頻，短促，是柴火的劈啪感
   * 最後補一顆下滑的正弦當火焰底部的悶響。
   * @param k 強度（0.6 = 普通斬、1 = 重擊、1.5 = 龍形/終結）
   */
  fire(k = 1) {
    try {
      const ctx = this._ensure();
      const t0 = ctx.currentTime;
      const dur = 0.32 + 0.24 * k;

      const roar = ctx.createBufferSource();
      roar.buffer = this._noise;
      roar.playbackRate.value = 0.55;         // 放慢 = 顆粒變粗，比較像火不像沙沙聲
      const lp = ctx.createBiquadFilter();
      lp.type = 'lowpass';
      lp.Q.value = 6;
      lp.frequency.setValueAtTime(160, t0);
      lp.frequency.exponentialRampToValueAtTime(900 + 400 * k, t0 + 0.07);
      lp.frequency.exponentialRampToValueAtTime(110, t0 + dur);
      const rg = ctx.createGain();
      rg.gain.setValueAtTime(0.0001, t0);
      rg.gain.exponentialRampToValueAtTime(0.34 * k, t0 + 0.03);
      rg.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
      roar.connect(lp).connect(rg).connect(ctx.destination);
      roar.start(t0);
      roar.stop(t0 + dur + 0.05);

      const crack = ctx.createBufferSource();
      crack.buffer = this._noise;
      crack.playbackRate.value = 1.6;
      const cbp = ctx.createBiquadFilter();
      cbp.type = 'bandpass';
      cbp.Q.value = 3.2;
      cbp.frequency.setValueAtTime(1500, t0);
      cbp.frequency.exponentialRampToValueAtTime(4200, t0 + 0.12);
      const cg = ctx.createGain();
      cg.gain.setValueAtTime(0.0001, t0 + 0.01);
      cg.gain.exponentialRampToValueAtTime(0.15 * k, t0 + 0.04);
      cg.gain.exponentialRampToValueAtTime(0.0001, t0 + 0.2);
      crack.connect(cbp).connect(cg).connect(ctx.destination);
      crack.start(t0);
      crack.stop(t0 + 0.26);

      const sub = ctx.createOscillator();
      sub.type = 'sine';
      sub.frequency.setValueAtTime(90 * (1 + 0.3 * k), t0);
      sub.frequency.exponentialRampToValueAtTime(38, t0 + dur * 0.8);
      const sg = ctx.createGain();
      sg.gain.setValueAtTime(0.0001, t0);
      sg.gain.exponentialRampToValueAtTime(0.2 * k, t0 + 0.02);
      sg.gain.exponentialRampToValueAtTime(0.0001, t0 + dur * 0.85);
      sub.connect(sg).connect(ctx.destination);
      sub.start(t0);
      sub.stop(t0 + dur);
    } catch { /* 同上 */ }
  }
}
