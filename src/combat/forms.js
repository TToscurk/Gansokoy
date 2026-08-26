// 日之呼吸十三型 —— 純資料表，引擎（combat.js）不認識任何型的內容。
//
// 每型的欄位：
//   name    招式名（出招時閃在畫面上）
//   dmg     傷害（雜魚妖精 hp 40，大部分型 1~2 刀一隻）
//   range   判定半徑（公尺，從玩家腳下算）
//   arc     判定扇形角（弧度）。Math.PI*2 = 全周（旋轉斬）
//   lunge   出招瞬間的位移衝量（負值 = 後撤）
//   dur     動作長度（秒）＝ 出招節奏。動作演完就能接下一招，沒有額外冷卻，
//           所以「這一型有多快」完全由這個值決定
//   flags   thrust=突刺（窄長）、aoe=全周、heavy=重擊（頓挫）、
//           multi=N 段、dragon=龍形大斬、finisher=十三型大收招
//   motion  身體動作的名字，關鍵影格在 motion.js。十三型各有各的一套，
//           改動作只動那邊；這裡只負責「哪一型配哪一套」

export const FORMS = [
  { name: '壹之型・圓舞',           dmg: 34, range: 4.6, arc: Math.PI * 2, lunge:  0.6, dur: 0.42, aoe: true, motion: 'waltz' },
  { name: '貳之型・碧羅之天',       dmg: 40, range: 5.2, arc: 2.0,         lunge:  1.2, dur: 0.38, vertical: true, motion: 'skyRend' },
  { name: '參之型・烈日紅鏡',       dmg: 30, range: 5.6, arc: 2.6,         lunge:  0.8, dur: 0.34, motion: 'redMirror' },
  { name: '肆之型・幻日虹',         dmg: 26, range: 4.2, arc: 1.6,         lunge:  3.2, dur: 0.36, multi: 3, motion: 'mirageRainbow' },
  { name: '伍之型・火車',           dmg: 46, range: 5.0, arc: 1.9,         lunge:  1.4, dur: 0.44, heavy: true, motion: 'fireWheel' },
  { name: '陸之型・灼骨炎陽',       dmg: 38, range: 6.4, arc: 0.9,         lunge:  1.0, dur: 0.36, thrust: true, motion: 'boneSun' },
  { name: '柒之型・陽華突',         dmg: 36, range: 7.2, arc: 0.7,         lunge:  2.6, dur: 0.32, thrust: true, motion: 'sunPierce' },
  { name: '捌之型・斜陽轉身',       dmg: 32, range: 4.8, arc: Math.PI * 2, lunge: -1.2, dur: 0.40, aoe: true, motion: 'sunsetTurn' },
  { name: '玖之型・飛輪陽炎',       dmg: 28, range: 5.4, arc: 2.4,         lunge:  1.0, dur: 0.32, multi: 2, motion: 'flyingWheel' },
  { name: '拾之型・輝輝恩光',       dmg: 52, range: 5.2, arc: 1.8,         lunge:  1.6, dur: 0.48, heavy: true, motion: 'radiance' },
  { name: '拾壹之型・日暈之龍・頭舞', dmg: 58, range: 6.0, arc: 2.2,        lunge:  2.0, dur: 0.52, dragon: true, motion: 'dragonHead' },
  { name: '拾貳之型・炎舞',         dmg: 36, range: 4.8, arc: Math.PI * 2, lunge:  0.8, dur: 0.40, aoe: true, motion: 'flameDance' },
  { name: '拾參之型・輪廻',         dmg: 72, range: 6.6, arc: Math.PI * 2, lunge:  2.4, dur: 0.62, aoe: true, finisher: true, motion: 'rinne' },
];

// 日之呼吸的配色：橘（日輪）為核心、藍（氣流）為外緣。
// VFX 與 UI 都從這裡取色，改色只動這兩行。
export const BREATH_CORE = 0xff7a1a;   // 橘
export const BREATH_EDGE = 0x3a7aff;   // 藍
