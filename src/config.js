// 世界尺度與方位（從 gensokyo-3d 搬來，給 NPC 系統用地區座標）
// ---------------------------------------------------------------------------
// 座標約定：  +X = 東    -X = 西    -Z = 北    +Z = 南

export const WORLD = {
  size: 2400,
  waterLevel: 0,
  gravity: -26,
};

export const COMPASS = [
  { a: 0,           zh: '北', en: 'N' },
  { a: Math.PI / 4, zh: '東北', en: 'NE' },
  { a: Math.PI / 2, zh: '東', en: 'E' },
  { a: Math.PI * 0.75, zh: '東南', en: 'SE' },
  { a: Math.PI,     zh: '南', en: 'S' },
  { a: Math.PI * 1.25, zh: '西南', en: 'SW' },
  { a: Math.PI * 1.5, zh: '西', en: 'W' },
  { a: Math.PI * 1.75, zh: '西北', en: 'NW' },
];

export const REGIONS = [
  // ---- 西北：妖怪之山系 ----
  {
    id: 'youkaiMountain', zh: '妖怪之山', en: 'YOUKAI MOUNTAIN', dir: '西北',
    x: -640, z: -690, elev: 150, radius: 360, rough: 26, peak: true,
    peakH: 225, craterR: 56, craterDepth: 26, rimH: 26,
    fog: 0x8fa4b4, accent: 0x6f8fbf, warp: [-408, -536],
  },
  {
    id: 'moriya', zh: '守矢神社', en: 'MORIYA SHRINE', dir: '西北',
    x: -598, z: -648, elev: 352, radius: 62, rough: 1.2,
    fog: 0xbcd0e4, accent: 0x3f8fc2,
  },
  {
    id: 'lake', zh: '霧之湖', en: 'MISTY LAKE', dir: '北西',
    x: -430, z: -400, elev: -14, radius: 195, rough: 1.0,
    fog: 0xc3d6e2, accent: 0x8fd8ee,
  },
  {
    id: 'sdm', zh: '紅魔館', en: 'SCARLET DEVIL MANSION', dir: '西北',
    x: -700, z: -270, elev: 36, radius: 175, rough: 1.2,
    fog: 0xb08088, accent: 0xd0263a,
  },

  // ---- 東：博麗神社（結界線上） ----
  {
    id: 'shrine', zh: '博麗神社', en: 'HAKUREI SHRINE', dir: '東',
    x: 855, z: -175, elev: 104, radius: 185, rough: 1.6,
    fog: 0x9fb4cc, accent: 0xc2382f,
  },

  // ---- 中央 ----
  {
    id: 'village', zh: '人間之里', en: 'HUMAN VILLAGE', dir: '中央',
    x: -80, z: 150, elev: 15, radius: 205, rough: 0.8,
    fog: 0xb8c4d0, accent: 0xd9b26a,
  },
  {
    id: 'myouren', zh: '命蓮寺', en: 'MYOUREN TEMPLE', dir: '西',
    x: -455, z: 70, elev: 28, radius: 120, rough: 1.2,
    fog: 0xc8bcd8, accent: 0xb98fd8,
  },
  {
    id: 'kourindou', zh: '香霖堂', en: 'KOURINDOU', dir: '西南',
    x: -235, z: 340, elev: 19, radius: 82, rough: 1.0,
    fog: 0xc4bca8, accent: 0x8a7a5a,
  },

  // ---- 西南～南：魔法之森與其後方的竹林 ----
  {
    id: 'forest', zh: '魔法之森', en: 'FOREST OF MAGIC', dir: '西南',
    x: -420, z: 570, elev: 26, radius: 250, rough: 6.5,
    fog: 0x4a5f4c, accent: 0x7dd88a,
  },
  {
    id: 'muenzuka', zh: '無緣塚', en: 'MUENZUKA', dir: '西南',
    x: -640, z: 760, elev: 22, radius: 95, rough: 2.4,
    fog: 0x7a6f80, accent: 0xc890d8,
  },
  {
    id: 'bamboo', zh: '迷途竹林', en: 'BAMBOO FOREST OF THE LOST', dir: '南',
    x: -60, z: 840, elev: 17, radius: 235, rough: 3.0,
    fog: 0x8fae86, accent: 0xa8c96a,
  },

  // ---- 東南 ----
  {
    id: 'namelessHill', zh: '無名之丘', en: 'NAMELESS HILL', dir: '東南',
    x: 430, z: 640, elev: 68, radius: 175, rough: 5.0,
    fog: 0xc8d4b8, accent: 0xd8e8a0,
  },
  {
    id: 'sunflower', zh: '太陽花田', en: 'GARDEN OF THE SUN', dir: '東南',
    x: 660, z: 330, elev: 32, radius: 200, rough: 1.4,
    fog: 0xe4d090, accent: 0xf2c832,
  },

  // ---- 天狗聚落 ----
  {
    id: 'tenguVillage', zh: '天狗聚落', en: 'TENGU SETTLEMENT', dir: '西北',
    x: -840, z: -590, elev: 142, radius: 78, rough: 3.2,
    fog: 0xa8bcce, accent: 0x8a9ab0,
    warp: [-832, -566],
  },

  // ---- 結界之外 ----
  {
    id: 'netherworld', zh: '白玉樓', en: 'HAKUGYOKUROU', dir: '結界之外', remote: true,
    x: 620, z: -760, elev: 168, radius: 190, rough: 2.0,
    fog: 0xe6c2d4, accent: 0xf2a8c4,
  },
  {
    id: 'tenkai', zh: '天界', en: 'BHAVA-AGRA', dir: '天空', remote: true,
    x: 350, z: -880, elev: 340, radius: 130, rough: 1.2,
    fog: 0xdce8f4, accent: 0xf4d8b0,
  },
  {
    id: 'higan', zh: '彼岸', en: 'HIGAN', dir: '結界之外', remote: true,
    x: 950, z: -550, elev: -6, radius: 150, rough: 1.6,
    fog: 0x9098a4, accent: 0xd8305a,
  },
];

export const REGION_BY_ID = Object.fromEntries(REGIONS.map(r => [r.id, r]));
