// 地面網格 + 「與渲染結果完全一致」的高度查詢 —— 鋪地物件防閃爍的根治。
//
// 之前路面閃爍/草蓋到路修過一輪（貼地 + polygonOffset），但在起伏較大的
// 圖上還是會漏：**路面抬的是解析高度 heightAt(x,z) + 4cm，地面畫的卻是
// 每 4 公尺一格的線性內插**。高度場裡的高頻項（土路顛簸的 wob、河床邊緣）
// 在兩個網格頂點之間的真實曲率誤差可以到 ±10cm —— 比 4cm 的抬升還大，
// 草皮自然就從路面中間穿出來。
//
// 根治的辦法不是把 lift 調大（會看出路浮著），而是讓路面每個頂點都問
// 「地面網格在這個點**實際畫出來**的高度」再抬 lift。這個檔案就是那個
// 「實際畫出來的高度」：把高度表存下來，sample() 用跟 PlaneGeometry
// 完全相同的三角形切分做內插 —— 連對角線方向都一致，所以誤差是零。

import * as THREE from 'three';

export class GroundGrid {
  /**
   * @param {object} o
   * @param {number} o.size 邊長（正方形，中心在原點）
   * @param {number} o.seg  每邊格數
   * @param {(x:number,z:number)=>number} o.heightAt 解析高度場
   */
  constructor({ size, seg, heightAt }) {
    this.size = size;
    this.seg = seg;
    this.heightAt = heightAt;
    this.step = size / seg;
    this.half = size / 2;

    const n = seg + 1;
    this.h = new Float32Array(n * n);
    for (let j = 0; j < n; j++) {
      for (let i = 0; i < n; i++) {
        this.h[j * n + i] = heightAt(-this.half + i * this.step, -this.half + j * this.step);
      }
    }
  }

  /**
   * 地面網格在 (x,z) 實際渲染的高度。
   * 跟 PlaneGeometry 的三角形切分完全一致（每格對角線 a-d，
   * 三角形 (a,b,d) 與 (b,c,d)），不是雙線性 —— 差那一點就會閃。
   * 超出網格範圍退回解析高度。
   */
  sample(x, z) {
    const { seg, step, half, h } = this;
    const fx = (x + half) / step, fz = (z + half) / step;
    if (fx < 0 || fz < 0 || fx >= seg || fz >= seg) return this.heightAt(x, z);
    const i = Math.floor(fx), j = Math.floor(fz);
    const u = fx - i, v = fz - j;
    const n = seg + 1;
    const ha = h[j * n + i];             // (i, j)
    const hb = h[(j + 1) * n + i];       // (i, j+1)
    const hc = h[(j + 1) * n + i + 1];   // (i+1, j+1)
    const hd = h[j * n + i + 1];         // (i+1, j)
    // PlaneGeometry 的兩個三角形：(a,b,d) 蓋 u+v<=1、(b,c,d) 蓋 u+v>=1
    if (u + v <= 1) return ha + (hb - ha) * v + (hd - ha) * u;
    return hc + (hb - hc) * (1 - u) + (hd - hc) * (1 - v);
  }

  /** 依高度表建位移過的地面幾何（頂點值與 sample() 完全同源） */
  buildGeometry() {
    const { size, seg, h } = this;
    const geo = new THREE.PlaneGeometry(size, size, seg, seg);
    geo.rotateX(-Math.PI / 2);
    const p = geo.attributes.position;
    const n = seg + 1;
    // rotateX(-90°) 後：x 隨 ix 遞增、z 隨 iy 遞增 —— 跟高度表同一個順序
    for (let j = 0; j < n; j++) {
      for (let i = 0; i < n; i++) {
        p.setY(j * n + i, h[j * n + i]);
      }
    }
    geo.computeVertexNormals();
    return geo;
  }
}

/**
 * 沿中心線鋪一條貼地帶子（路面）。每個頂點都用 grid.sample() 取
 * 「地面實際渲染的高度」再抬 lift —— 永遠不會被草皮穿出來。
 * @param {THREE.Object3D} parent
 * @param {[number,number][]} dense 已細分好的中心線點列
 * @param {number} halfW 半寬
 * @param {THREE.Material} mat 需開 polygonOffset 的鋪地材質
 * @param {(x:number,z:number)=>number} sample GroundGrid.sample（bind 過的）
 */
export function ribbonOnGrid(parent, dense, halfW, mat, sample, lift = 0.05) {
  const pos = [], uv = [], idx = [];
  for (let i = 0; i < dense.length; i++) {
    const [cx, cz] = dense[i];
    const a = dense[Math.max(0, i - 1)], b = dense[Math.min(dense.length - 1, i + 1)];
    const tx = b[0] - a[0], tz = b[1] - a[1];
    const tl = Math.hypot(tx, tz) || 1;
    const nx = tz / tl, nz = -tx / tl;
    for (const sgn of [-1, 1]) {
      const x = cx + nx * halfW * sgn, z = cz + nz * halfW * sgn;
      pos.push(x, sample(x, z) + lift, z);
      uv.push(sgn > 0 ? 1 : 0, i * 0.16);
    }
    if (i < dense.length - 1) {
      // 繞向決定面朝上還是朝下 —— 反了整條路會被背面剔除
      const k = i * 2;
      idx.push(k, k + 2, k + 1, k + 1, k + 2, k + 3);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  const m = new THREE.Mesh(geo, mat);
  m.receiveShadow = true;
  parent.add(m);
  return m;
}

/**
 * 矩形鋪地（石板路、水田）。細分 + 每頂點貼地，同 ribbonOnGrid 的原理。
 */
export function decalOnGrid(parent, w, d, x, z, mat, sample, lift = 0.05) {
  const geo = new THREE.PlaneGeometry(w, d, Math.max(1, Math.round(w / 2)), Math.max(1, Math.round(d / 2)));
  geo.rotateX(-Math.PI / 2);
  const p = geo.attributes.position;
  for (let i = 0; i < p.count; i++) {
    p.setY(i, sample(p.getX(i) + x, p.getZ(i) + z) + lift);
  }
  geo.computeVertexNormals();
  const m = new THREE.Mesh(geo, mat);
  m.position.set(x, 0, z);
  m.receiveShadow = true;
  parent.add(m);
  return m;
}
