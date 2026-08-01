// 全區地圖登記表 —— 整個幻想鄉的「哪裡通哪裡」只寫在這一份。
//
// config.js 的 REGIONS 管世界座標與氛圍（fog/accent），這裡管遊戲層：
// 建好了沒（built）、通往哪些圖（connections）、掛哪種怪（mobTheme）、
// 遊玩範圍多大（playSize）、是不是安全區（safe）。
//
// connections 是**單一事實來源**：每張圖的傳送點、HUD 提示、之後的
// 世界地圖 UI 都應該從這裡讀，不要在各地圖檔案裡各寫一份 —— 兩份
// 名單遲早會漂移。有兩條連線是設計上可改的（規格書 v4 標 ⚙️）：
//   1. village ↔ lake：河畔道。不要的話刪掉這一對，改從 trail 開西臂。
//   2. trail ↔ sunflower：環線閉合點。改接人里的話搬去 village。
//
// 設計決定（寫死在 bamboo.js 的註解，這裡遵守）：人里**不**直通竹林，
// 去竹林一定得經獸道岔路 —— 那條分岔才有存在感。

import { REGION_BY_ID } from '../config.js';

/**
 * 遊戲層資料。id 對齊 REGIONS；只在 REGIONS 有、這裡沒有的條目視為
 * 「純座標、無地圖」。反過來（這裡有、REGIONS 沒有）也允許 ——
 * 獸道就是這種：它是連接用的路，不是原始世界的一個「地區」，
 * 沒有 REGION 座標，但它是一張真實存在的圖，connections 的樞紐。
 */
const MAP_INFO = {
  shrine: {
    built: true, safe: true, playSize: [150, 110], mobTheme: null,
    connections: ['trail'],
    entry: 'index.html',
  },
  trail: {
    built: true, safe: false, playSize: [680, 680], mobTheme: 'fairy',
    connections: ['shrine', 'village', 'bamboo', 'sunflower'],   // 第四臂 = 環線閉合 ⚙️
    entry: 'maps/trail/',
    // 無 REGION 的圖要自帶名字；座標取三臂端點的幾何中心附近（世界地圖 UI 用）
    zh: '獸道', en: 'BEAST TRAIL', x: 240, z: 270,
  },
  village: {
    built: true, safe: true, playSize: [460, 460], mobTheme: null,
    connections: ['trail', 'kourindou', 'myouren', 'lake'],      // lake = 河畔道 ⚙️
    entry: 'maps/village/',
  },
  bamboo: {
    built: true, safe: false, playSize: [300, 600], mobTheme: 'rabbit',
    connections: ['trail', 'eientei', 'namelessHill'],
    entry: 'maps/bamboo/',
  },
  namelessHill: {
    built: true, safe: false, playSize: [220, 220], mobTheme: 'hazard',   // 花海毒區，無實體怪
    connections: ['bamboo', 'sunflower'],
    entry: 'maps/namelessHill/',
  },

  eientei: {
    built: true, safe: true, playSize: [200, 180], mobTheme: null,
    connections: ['bamboo'],
    entry: 'maps/eientei/',
  },

  // ---- 待建（第二期起逐張補 built: true） ----
  sunflower: {
    built: true, safe: false, playSize: [360, 360], mobTheme: 'flowerFairy',
    connections: ['namelessHill', 'trail'],
    entry: 'maps/sunflower/',
  },
  kourindou: {
    built: true, safe: true, playSize: [140, 140], mobTheme: null,
    connections: ['village', 'forest'],
    entry: 'maps/kourindou/',
  },
  forest: {
    built: false, safe: false, playSize: [450, 450], mobTheme: 'beast',    // + 孢子毒區
    connections: ['kourindou', 'muenzuka'],
  },
  muenzuka: {
    built: false, safe: false, playSize: [280, 280], mobTheme: 'ghost',
    connections: ['forest', 'higan'],
  },
  lake: {
    built: false, safe: false, playSize: [400, 400], mobTheme: 'iceFairy',
    connections: ['village', 'youkaiMountain', 'sdm'],
  },
  sdm: {
    built: false, safe: false, playSize: [280, 220], mobTheme: 'maid',     // 外庭 + 室內兩段
    connections: ['lake'],
  },
  youkaiMountain: {
    built: false, safe: false, playSize: [560, 560], mobTheme: 'kappaTengu',
    connections: ['lake', 'moriya', 'tenguVillage', 'higan'],
  },
  moriya: {
    built: false, safe: true, playSize: [180, 180], mobTheme: null,
    connections: ['youkaiMountain'],
  },
  tenguVillage: {
    built: false, safe: true, playSize: [220, 220], mobTheme: null,
    connections: ['youkaiMountain'],
  },
  myouren: {
    built: false, safe: true, playSize: [200, 200], mobTheme: null,
    connections: ['village'],
  },
  netherworld: {
    built: false, safe: true, playSize: [300, 260], mobTheme: 'ghost',     // 幽靈無害，做氛圍
    connections: [],   // 事件限定：神社夜間 22:00–02:00 裂縫
  },
  higan: {
    built: false, safe: true, playSize: [280, 200], mobTheme: null,
    connections: ['muenzuka', 'youkaiMountain'],
  },
  tenkai: {
    built: false, safe: true, playSize: [240, 200], mobTheme: null,
    connections: [],   // 事件限定：妖怪之山山頂傳送
  },
};

/** 完整登記表：REGIONS 的座標/氛圍 + 上面的遊戲層欄位。
 *  以 MAP_INFO 為準（漏 filter REGIONS 會把 trail 這種無 REGION 的圖整個吃掉）。 */
export const MAP_REGISTRY = Object.fromEntries(
  Object.keys(MAP_INFO).map(id =>
    [id, { id, ...(REGION_BY_ID[id] ?? {}), ...MAP_INFO[id] }])
);

/** 兩張圖之間有沒有路（雙向認定 —— 有一邊漏寫就吵出來） */
export function connected(a, b) {
  const fa = MAP_REGISTRY[a]?.connections.includes(b);
  const fb = MAP_REGISTRY[b]?.connections.includes(a);
  if (fa !== fb) console.error(`[mapRegistry] 連線不對稱：${a}→${b}=${fa} 但 ${b}→${a}=${fb}`);
  return !!(fa && fb);
}

// 載入時自檢：connections 裡的每個 id 都必須在登記表裡，而且要對稱
for (const [id, m] of Object.entries(MAP_REGISTRY)) {
  for (const to of m.connections) {
    if (!MAP_REGISTRY[to]) {
      console.error(`[mapRegistry] ${id} 連到不存在的圖：${to}`);
    } else if (!MAP_REGISTRY[to].connections.includes(id)) {
      console.error(`[mapRegistry] 連線不對稱：${id}→${to} 有、${to}→${id} 沒有`);
    }
  }
}

export { REGION_BY_ID };
