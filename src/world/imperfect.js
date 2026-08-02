// 不對稱與不完美（地圖品質升級書・升級 7 第 4 點）。
//
// 「完美整齊＝佈景感」。但反過來把每樣東西都弄歪也不對 —— 那是均勻的雜訊，
// 讀起來是「這個世界在抖」，不是「這裡有人住」。真實的地方是：**大部分東西
// 整齊，少數幾樣明顯壞掉**。壞掉的那幾樣才是故事。
//
// 所以第 4 點拆成兩層，這個檔案只負責第一層：
//
//   第一層（這裡）：對已經擺好的物件抽一小部分做細微擾動 —— 歪一點、沉一點、
//                   大小差一點。它不該被「看見」，只該讓整排東西不再像複製貼上。
//   第二層（各地圖自己寫）：每張圖三處以上**看得見**的破綻 —— 圍牆缺一段、
//                   某盞燈籠歪 15 度、有一戶屋頂搭著鷹架在補瓦。
//
// 用法（一定要在 mergeStaticByMaterial 之前呼叫，合併之後就動不了了）：
//   scuff(lanterns, { seed: 5 });
//   scuff(world, { rate: 0.3, filter: o => o.userData.kind === 'fence' });
//
// 想讓某個東西完全不被動到，掛 userData.noScuff = true。

import * as THREE from 'three';

function rng(seed = 1) {
  let s = (seed >>> 0) || 1;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0), s / 4294967296);
}

/**
 * 對一組物件抽一部分做細微擾動。
 *
 * 預設值刻意小：偏轉不到 2 度、沉降 3 公分。**碰撞盒不會跟著動** ——
 * 這些圖的碰撞盒是另外註冊的軸對齊方塊，所以擾動必須小到「玩家撞到的地方
 * 跟看到的地方對得上」。要更誇張的破綻請用第二層手工擺，順便把碰撞盒一起改。
 *
 * @param {THREE.Object3D|THREE.Object3D[]} target
 *        傳陣列就處理陣列裡的每個；傳單一物件就處理它的直接子節點。
 * @param {object} [o]
 * @param {number} [o.seed=1]
 * @param {number} [o.rate=0.35] 動到的比例。**別調到 1** —— 全部都歪就變成
 *        均勻的雜訊，反而讀不出「有幾樣壞掉」。
 * @param {number} [o.yaw=0.03]  繞 Y 的最大偏轉（弧度，約 1.7 度）
 * @param {number} [o.tilt=0.02] 前後左右傾斜的最大角度（約 1.1 度）
 * @param {number} [o.sink=0.03] 上下的最大偏移（公尺）
 * @param {number} [o.scale=0.02] 大小的最大偏差（比例）
 * @param {(o:THREE.Object3D)=>boolean} [o.filter] 再篩一層，回傳 false 就跳過
 * @returns {number} 實際動到幾個（回傳值是給驗證腳本斷言用的）
 */
export function scuff(target, {
  seed = 1, rate = 0.35, yaw = 0.03, tilt = 0.02, sink = 0.03, scale = 0.02,
  filter = null,
} = {}) {
  const list = Array.isArray(target) ? target : (target?.children ?? []).slice();
  const rand = rng(seed);
  let n = 0;
  for (const o of list) {
    if (!o || o.userData?.noScuff) continue;
    if (filter && !filter(o)) continue;
    // 每個物件都抽一次骰，不管抽不抽得中 —— 這樣 rate 改了之後，
    // 沒被選中的那些的亂數序列不會整個位移，比對截圖才有意義
    const pick = rand() < rate;
    const r = [rand(), rand(), rand(), rand(), rand()];
    if (!pick) continue;
    o.rotation.y += (r[0] - 0.5) * 2 * yaw;
    o.rotation.x += (r[1] - 0.5) * 2 * tilt;
    o.rotation.z += (r[2] - 0.5) * 2 * tilt;
    o.position.y += (r[3] - 0.5) * 2 * sink;
    const s = 1 + (r[4] - 0.5) * 2 * scale;
    o.scale.multiplyScalar(s);
    o.updateMatrix();
    n++;
  }
  return n;
}

/**
 * 讓一組共用同一份材質的物件，各自的顏色差一點點。
 *
 * 為什麼需要：同一批木頭不會是同一個色。但直接改共用材質會改到全部，
 * 所以這裡是**每個物件複製一份材質**再各自偏色 —— 代價是 draw call
 * 不再合併，所以只對「數量少、看得近」的東西用（門柱、招牌、燈籠），
 * 一整排柵欄不要用。
 *
 * @param {THREE.Object3D[]} objs
 * @param {object} [o]
 * @param {number} [o.seed=1]
 * @param {number} [o.hue=0.012] 色相的最大偏移
 * @param {number} [o.sat=0.06]  飽和度的最大偏移
 * @param {number} [o.lum=0.07]  亮度的最大偏移
 * @returns {number} 實際動到幾個
 */
export function tint(objs, { seed = 1, hue = 0.012, sat = 0.06, lum = 0.07 } = {}) {
  const rand = rng(seed);
  const hsl = {};
  let n = 0;
  for (const o of objs) {
    if (!o?.isMesh || o.userData?.noScuff) continue;
    const src = Array.isArray(o.material) ? o.material[0] : o.material;
    if (!src?.color) continue;
    const m = src.clone();
    m.color.getHSL(hsl);
    m.color.setHSL(
      (hsl.h + (rand() - 0.5) * 2 * hue + 1) % 1,
      THREE.MathUtils.clamp(hsl.s + (rand() - 0.5) * 2 * sat, 0, 1),
      THREE.MathUtils.clamp(hsl.l + (rand() - 0.5) * 2 * lum, 0, 1),
    );
    o.material = m;
    o.userData.noMerge = true;   // 各自一份材質，合併批次會把它們拆回來，乾脆別進去
    n++;
  }
  return n;
}
