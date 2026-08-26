// 色調分級 LUT（材質與畫質升級書・第 4.4 節）
//
// 目的：讓每個地區有明確的色調個性（魔法之森偏冷綠、太陽花田偏暖）。
// 只調 fog 色只影響遠處，LUT 影響整個畫面的每一個像素，深刻得多。
//
// 為什麼是「程序生成」而不是讀 .cube 檔：這個專案不下載任何外部資產。
// 這裡用一組看得懂的參數（色溫、lift/gamma/gain、飽和、陰影／高光染色）
// 去烘出查找表 —— 想調色改參數就好，不必開調色軟體。
//
// 為什麼是 2D 條狀圖而不是 Data3DTexture：sampler3D 要 GLSL3，而後製鏈
// 那支 ShaderPass 是 GLSL1。條狀 LUT（N 個切片橫向排開）用 texture2D 就
// 能取樣，相容性最好，代價只是自己做一次藍色軸的內插。

import * as THREE from 'three';

/** sRGB 亮度係數（跟 grade shader、texgen 用同一組） */
const LUMA = [0.2126, 0.7152, 0.0722];

const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);

/**
 * 烘一張色調分級 LUT。
 *
 * 參數的套用順序是有意義的，跟調色台一致：
 *   色溫 → lift/gamma/gain → 陰影/高光染色 → 飽和度
 *
 * @param {object} [o]
 * @param {number} [o.size=16] 每軸格數。16 已經很夠，32 只是變四倍大。
 * @param {number} [o.temp=0] 色溫。正＝暖（加紅減藍），負＝冷。±0.15 就很明顯。
 * @param {number} [o.tintGM=0] 洋紅↔綠。正＝偏綠，負＝偏洋紅。
 * @param {number} [o.lift=0] 暗部整體抬升（給霧感／褪色感）
 * @param {number} [o.gamma=1] 中間調。>1 變暗，<1 變亮。
 * @param {number} [o.gain=1] 亮部增益
 * @param {number} [o.sat=1] 飽和度
 * @param {string|null} [o.shadowTint=null] 陰影染色
 * @param {number} [o.shadowAmt=0.12]
 * @param {string|null} [o.highlightTint=null] 高光染色
 * @param {number} [o.highlightAmt=0.10]
 * @returns {THREE.DataTexture} 寬 size²、高 size 的條狀 LUT
 */
export function buildLUT({
  size = 16, temp = 0, tintGM = 0, lift = 0, gamma = 1, gain = 1, sat = 1,
  shadowTint = null, shadowAmt = 0.12, highlightTint = null, highlightAmt = 0.10,
} = {}) {
  const N = size;
  const W = N * N, H = N;
  const data = new Uint8Array(W * H * 4);

  const sh = shadowTint ? new THREE.Color(shadowTint) : null;
  const hi = highlightTint ? new THREE.Color(highlightTint) : null;

  for (let b = 0; b < N; b++) {
    for (let g = 0; g < N; g++) {
      for (let r = 0; r < N; r++) {
        let c = [r / (N - 1), g / (N - 1), b / (N - 1)];

        // 色溫／色調：紅藍對推、綠對洋紅
        c[0] = clamp01(c[0] + temp * 0.5);
        c[2] = clamp01(c[2] - temp * 0.5);
        c[1] = clamp01(c[1] + tintGM * 0.5);

        // lift / gamma / gain
        for (let i = 0; i < 3; i++) {
          let v = c[i];
          v = lift + v * (1 - lift);            // 抬暗部，白點不動
          v = Math.pow(clamp01(v), gamma);
          v = clamp01(v * gain);
          c[i] = v;
        }

        const l = c[0] * LUMA[0] + c[1] * LUMA[1] + c[2] * LUMA[2];

        // 陰影／高光分別染色 —— 這是「地區個性」最有效的一招，
        // 整體染會變成濾鏡，只染一端才像打光
        if (sh) {
          const k = (1 - l) * (1 - l) * shadowAmt;
          c[0] += (sh.r - c[0]) * k; c[1] += (sh.g - c[1]) * k; c[2] += (sh.b - c[2]) * k;
        }
        if (hi) {
          const k = l * l * highlightAmt;
          c[0] += (hi.r - c[0]) * k; c[1] += (hi.g - c[1]) * k; c[2] += (hi.b - c[2]) * k;
        }

        // 飽和度放最後，前面染的色才會被一起考慮進去
        const l2 = c[0] * LUMA[0] + c[1] * LUMA[1] + c[2] * LUMA[2];
        for (let i = 0; i < 3; i++) c[i] = clamp01(l2 + (c[i] - l2) * sat);

        // 條狀排列：第 b 個切片往右擺 b*N 個像素
        const x = b * N + r, y = g;
        const p = (y * W + x) * 4;
        data[p] = c[0] * 255; data[p + 1] = c[1] * 255; data[p + 2] = c[2] * 255; data[p + 3] = 255;
      }
    }
  }

  const tex = new THREE.DataTexture(data, W, H, THREE.RGBAFormat);
  // LUT 是資料不是顏色 —— 標成 sRGB 會被再解碼一次，整條曲線就歪了
  tex.colorSpace = THREE.NoColorSpace;
  tex.minFilter = tex.magFilter = THREE.LinearFilter;
  tex.wrapS = tex.wrapT = THREE.ClampToEdgeWrapping;
  tex.generateMipmaps = false;
  tex.needsUpdate = true;
  tex.userData.lutSize = N;
  return tex;
}

/**
 * 各地區的色調個性。抽出來放同一處，改的時候看得到彼此的關係 ——
 * 分散在各張圖裡的話，調完這張忘了那張，整個世界的色調就散了。
 */
export const LUT_PRESETS = {
  /** 神社：基準。略暖、對比稍高，日本朱紅要跳出來 */
  shrine: { temp: 0.03, sat: 1.04, highlightTint: '#ffe9c8', highlightAmt: 0.08 },
  /** 人間之里：生活感，暖而不豔 */
  village: { temp: 0.05, sat: 1.02, shadowTint: '#3a3350', shadowAmt: 0.10 },
  /** 迷途竹林：冷綠、壓低飽和，竹子的青才會冷 */
  bamboo: { temp: -0.05, tintGM: 0.04, sat: 0.96, lift: 0.03, shadowTint: '#1e3a34', shadowAmt: 0.16 },
  /** 永遠亭：月之都的清冷，偏藍 */
  eientei: { temp: -0.07, sat: 0.98, shadowTint: '#243052', shadowAmt: 0.18, highlightTint: '#e6ecff', highlightAmt: 0.10 },
  /** 香霖堂：森林邊緣，微冷偏綠 */
  kourindou: { temp: -0.03, tintGM: 0.03, sat: 0.99, shadowTint: '#26382e', shadowAmt: 0.12 },
  /** 無名之丘：開闊草原，清爽 */
  namelessHill: { temp: 0.01, tintGM: 0.02, sat: 1.03, highlightTint: '#f2ffe8', highlightAmt: 0.08 },
  /** 太陽花田：最暖，整張圖就是為了那片黃 */
  sunflower: { temp: 0.10, sat: 1.10, gain: 1.02, highlightTint: '#fff0c0', highlightAmt: 0.14 },
  /** 獸道：林間小徑，土色重、光少 */
  trail: { temp: 0.02, sat: 0.97, gamma: 1.04, shadowTint: '#2e2a22', shadowAmt: 0.14 },
};
