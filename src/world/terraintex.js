// 地形用的共用貼圖（材質與畫質升級書・第 3 章）
//
// 三平面貼圖要在陡坡上混一套「岩石」材質，七張圖都需要同一種石頭 ——
// 各圖各畫一份沒有意義，而且色調對不齊會讓相鄰地圖看起來像兩個世界。
//
// 這裡只負責「顏色」那一張，法線與粗糙度照樣交給 texgen.mapsFromTexture
// 推導，跟其他材質走同一條路。

import * as THREE from 'three';
import { fbm, ridged, worley, modulate, rng } from './noise.js';

/**
 * 裸岩。層理（ridged 沿一個方向拉長）＋ 顆粒（Worley）＋ 風化斑。
 *
 * @param {object} [o]
 * @param {number} [o.size=256]
 * @param {string} [o.base='#7b756a'] 基底色。各圖想偏暖偏冷可以自己給。
 * @param {number} [o.seed=0x0C0FFEE]
 * @returns {THREE.CanvasTexture}
 */
export function rockTexture({ size = 256, base = '#7b756a', seed = 0x0C0FFEE } = {}) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d', { willReadFrequently: true });
  const R = rng(seed);

  g.fillStyle = base;
  g.fillRect(0, 0, size, size);

  const k = 1 / size;
  modulate(g, size, (x, y) => {
    // 層理：橫向拉長的脊狀 noise，就是沉積岩一層一層的樣子
    const bed = ridged(x * k * 6, y * k * 22, { period: [6, 22], octaves: 4, seed: 3 });
    // 顆粒：石英一顆一顆的亮點
    const cell = worley(x * k * 30, y * k * 30, 30, 17);
    // 風化：大尺度的深淺
    const weather = fbm(x * k * 5, y * k * 5, { period: 5, octaves: 4, seed: 29 });
    return 0.74 + bed * 0.26 + Math.min(cell, 0.4) * 0.22 + weather * 0.16;
  }, { step: size >= 512 ? 2 : 1 });

  // 幾道明顯的裂隙。2D API 畫的邊緣才夠銳利，法線貼圖吃得到
  for (let i = 0; i < 14; i++) {
    g.strokeStyle = `rgba(58,54,48,${0.16 + R() * 0.2})`;
    g.lineWidth = 0.6 + R() * 1.4;
    let x = R() * size, y = R() * size;
    g.beginPath(); g.moveTo(x, y);
    for (let j = 0; j < 4; j++) {
      x += (R() - 0.5) * size * 0.4; y += (R() - 0.5) * size * 0.4;
      g.lineTo(x, y);
    }
    g.stroke();
  }

  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = 8;
  return t;
}
