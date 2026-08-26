// 火星場 —— 所有的火花/餘燼共用一個 Points，永遠只花一個 draw call。
//
// 原本每顆火花是一個 Mesh，40 顆就是 40 個 draw call；改成 Points 之後
// 上限拉到 640 顆反而更便宜。每顆自己帶大小與顏色（走自訂 shader，
// three 內建的 PointsMaterial 只能全體同一個 size）。
//
// 粒子只有 CPU 端積分：重力 + 阻力 + 隨壽命縮小變暗。additive 混合下
// 「變暗」就是「變透明」，所以不必碰 alpha。

import * as THREE from 'three';

const MAX = 640;
const GRAV = 13.5;

const VERT = `
attribute float aSize;
attribute vec3 aColor;
varying vec3 vColor;
void main() {
  vColor = aColor;
  vec4 mv = modelViewMatrix * vec4(position, 1.0);
  gl_PointSize = aSize * (320.0 / max(0.6, -mv.z));
  gl_Position = projectionMatrix * mv;
}`;

const FRAG = `
uniform sampler2D uMap;
varying vec3 vColor;
void main() {
  vec4 t = texture2D(uMap, gl_PointCoord);
  gl_FragColor = vec4(vColor, 1.0) * t;
}`;

function sparkTexture() {
  const cv = document.createElement('canvas');
  cv.width = cv.height = 32;
  const g = cv.getContext('2d');
  const gr = g.createRadialGradient(16, 16, 0, 16, 16, 16);
  gr.addColorStop(0, 'rgba(255,255,255,1)');
  gr.addColorStop(0.35, 'rgba(255,206,130,.75)');
  gr.addColorStop(1, 'rgba(255,150,50,0)');
  g.fillStyle = gr;
  g.fillRect(0, 0, 32, 32);
  return new THREE.CanvasTexture(cv);
}

const _c = new THREE.Color();

export class EmberField {
  constructor(scene) {
    this.scene = scene;
    this.n = 0;                       // 目前活著的顆數（活的永遠擠在陣列前段）

    this.pos = new Float32Array(MAX * 3);
    this.col = new Float32Array(MAX * 3);
    this.siz = new Float32Array(MAX);
    // 每顆的動態資料（不進 GPU）
    this.vel = new Float32Array(MAX * 3);
    this.rgb = new Float32Array(MAX * 3);   // 原始顏色，每幀乘上衰減
    this.life = new Float32Array(MAX);
    this.ttl = new Float32Array(MAX);
    this.s0 = new Float32Array(MAX);
    this.drag = new Float32Array(MAX);

    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(this.pos, 3));
    geo.setAttribute('aColor', new THREE.BufferAttribute(this.col, 3));
    geo.setAttribute('aSize', new THREE.BufferAttribute(this.siz, 1));
    geo.setDrawRange(0, 0);
    this.geo = geo;

    this.mesh = new THREE.Points(geo, new THREE.ShaderMaterial({
      uniforms: { uMap: { value: sparkTexture() } },
      vertexShader: VERT, fragmentShader: FRAG,
      transparent: true, depthWrite: false,
      blending: THREE.AdditiveBlending,
    }));
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 6;
    scene.add(this.mesh);
  }

  /**
   * 放一顆火星。
   * @param p    位置 {x,y,z}
   * @param v    初速 {x,y,z}
   * @param o    { color, size, ttl, drag }
   */
  spawn(p, v, o = {}) {
    // 滿了就吃掉最舊的一顆（前段是先生成的）
    const i = this.n < MAX ? this.n++ : 0;
    const i3 = i * 3;
    this.pos[i3] = p.x; this.pos[i3 + 1] = p.y; this.pos[i3 + 2] = p.z;
    this.vel[i3] = v.x; this.vel[i3 + 1] = v.y; this.vel[i3 + 2] = v.z;
    _c.set(o.color ?? 0xffb45a);
    this.rgb[i3] = _c.r; this.rgb[i3 + 1] = _c.g; this.rgb[i3 + 2] = _c.b;
    this.s0[i] = o.size ?? 0.22;
    this.ttl[i] = o.ttl ?? 0.45;
    this.life[i] = 0;
    this.drag[i] = o.drag ?? 1.6;
  }

  /** 一圈往外炸開的火星（命中、擊殺用）。 */
  burst(p, n, o = {}) {
    const spd = o.speed ?? 5;
    const up = o.up ?? 3;
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2 + Math.random() * 0.6;
      const s = spd * (0.45 + Math.random() * 0.9);
      this.spawn(p, {
        x: Math.cos(a) * s,
        y: up * (0.4 + Math.random()),
        z: Math.sin(a) * s,
      }, o);
    }
  }

  update(dt) {
    for (let i = this.n - 1; i >= 0; i--) {
      this.life[i] += dt;
      const t = this.life[i] / this.ttl[i];
      if (t >= 1) { this._kill(i); continue; }

      const i3 = i * 3;
      const d = Math.max(0, 1 - this.drag[i] * dt);
      this.vel[i3] *= d;
      this.vel[i3 + 1] = this.vel[i3 + 1] * d - GRAV * dt;
      this.vel[i3 + 2] *= d;
      this.pos[i3] += this.vel[i3] * dt;
      this.pos[i3 + 1] += this.vel[i3 + 1] * dt;
      this.pos[i3 + 2] += this.vel[i3 + 2] * dt;

      // 尾段收得比較快，看起來像燒完了
      const f = (1 - t) * (1 - t);
      this.col[i3] = this.rgb[i3] * f;
      this.col[i3 + 1] = this.rgb[i3 + 1] * f;
      this.col[i3 + 2] = this.rgb[i3 + 2] * f;
      this.siz[i] = this.s0[i] * (0.35 + f * 0.9);
    }

    this.geo.setDrawRange(0, this.n);
    if (this.n) {
      this.geo.attributes.position.needsUpdate = true;
      this.geo.attributes.aColor.needsUpdate = true;
      this.geo.attributes.aSize.needsUpdate = true;
    }
  }

  /** 用「拿最後一顆填補空位」保持活著的粒子擠在前段，drawRange 才切得乾淨。 */
  _kill(i) {
    const last = --this.n;
    if (i === last) return;
    const a = i * 3, b = last * 3;
    for (let k = 0; k < 3; k++) {
      this.pos[a + k] = this.pos[b + k];
      this.vel[a + k] = this.vel[b + k];
      this.rgb[a + k] = this.rgb[b + k];
      this.col[a + k] = this.col[b + k];
    }
    this.siz[i] = this.siz[last];
    this.s0[i] = this.s0[last];
    this.life[i] = this.life[last];
    this.ttl[i] = this.ttl[last];
    this.drag[i] = this.drag[last];
  }
}
