// 畫質設定 —— 全地圖共用的三檔（低/中/高）。
//
// 選擇存 localStorage：在任何一張圖調整，走到別張圖（或重開遊戲）
// 都維持同一檔。神社有完整的後製鏈，自己把檔位映射到 GTAO/Bloom
// 那一套（main.js 的 applyQuality）；獸道、人間之里這種沒有 composer
// 的圖用這裡的 applyBasicQuality（解析度 + 陰影貼圖大小）。
// 之後的新圖照樣：載入時 loadQualityIdx()，ESC 選單的畫質鈕接 cycle。

const KEY = 'gansokoy:quality';

export const QUALITY_NAMES = ['低', '中', '高'];

/** 沒有後製鏈的地圖用的三檔：渲染解析度 + 陰影貼圖 */
const BASIC = [
  { dpr: 0.8, shadow: 1024 },
  { dpr: 1.1, shadow: 2048 },
  { dpr: 1.5, shadow: 2048 },
];

export function loadQualityIdx(def = 2) {
  try {
    const v = parseInt(localStorage.getItem(KEY), 10);
    if (v >= 0 && v < QUALITY_NAMES.length) return v;
  } catch { /* 私隱模式 */ }
  return def;
}

export function saveQualityIdx(i) {
  try { localStorage.setItem(KEY, String(i)); } catch { /* 私隱模式 */ }
}

/**
 * 套用基本畫質（給沒有 composer 的地圖）。
 * @param {THREE.WebGLRenderer} renderer
 * @param {THREE.DirectionalLight} sun Environment 的太陽（陰影貼圖跟著檔位換）
 * @param {number} idx 0..2
 */
export function applyBasicQuality(renderer, sun, idx) {
  const q = BASIC[idx] ?? BASIC[2];
  renderer.setPixelRatio(Math.min(devicePixelRatio, q.dpr));
  renderer.setSize(innerWidth, innerHeight);
  if (sun && sun.shadow.mapSize.x !== q.shadow) {
    sun.shadow.mapSize.set(q.shadow, q.shadow);
    sun.shadow.map?.dispose();
    sun.shadow.map = null;
    sun.shadow.needsUpdate = true;
  }
}
