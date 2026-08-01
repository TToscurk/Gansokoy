// 大地圖（M 鍵）—— 幻想鄉的節點連線圖，全地圖共用。
//
// 資料完全來自 mapRegistry：節點位置用 REGIONS 的世界座標（+X 東、
// -Z 北 → 畫面上北在上），connections 畫成線，built:false 的圖畫成
// 虛線圈＋「？」——看得到方向、標得出「還沒開放」，但不假裝走得到。
// 事件限定圖（connections 空）畫成無連線的淡節點。
//
// 美術走手繪風：紙底色＋墨線＋硃砂色的現在地。刻意不做科技感 UI ——
// 這是幻想鄉，地圖應該像是文文。新聞社順手畫的那種。
//
// 驗收（升級5）：沒玩過的人一分鐘內能靠這張圖知道
// 「香霖堂在人里的西邊、魔法之森還沒開放」。

import { MAP_REGISTRY } from '../world/mapRegistry.js';

const CSS = `
#worldMap { position:fixed; inset:0; z-index:66; display:none;
  align-items:center; justify-content:center;
  background:rgba(10,8,6,.55); }
#worldMap.on { display:flex; }
#worldMap .frame { position:relative; box-shadow:0 30px 90px rgba(0,0,0,.7);
  border:1px solid rgba(60,44,28,.8); border-radius:2px; }
#worldMap canvas { display:block; }
#worldMap .hint { position:absolute; right:14px; bottom:10px; font-size:11px;
  letter-spacing:.2em; color:#6b5638; opacity:.75;
  font-family:"Noto Sans TC","Microsoft JhengHei",sans-serif; }
`;

/** 決定性亂數（紙的斑點、線的手抖 —— 每次開圖要長一樣） */
function lcg(seed) {
  let s = (seed * 2654435761) >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0), s / 4294967296);
}

/**
 * @param {object} o
 * @param {string} o.current  現在所在的圖 id（高亮＋「現在地」）
 * @param {() => boolean} [o.isBlocked]  對話/選單/編輯器開著時 M 不反應
 */
export function installWorldMap({ current, isBlocked = () => false }) {
  const style = document.createElement('style');
  style.textContent = CSS;
  document.head.appendChild(style);

  const wrap = document.createElement('div');
  wrap.id = 'worldMap';
  wrap.innerHTML = `<div class="frame"><canvas></canvas>
    <div class="hint">M / ESC　收起地圖</div></div>`;
  document.body.appendChild(wrap);
  const canvas = wrap.querySelector('canvas');

  const state = { isOpen: false };

  /* ------------------------------------------------ 佈局 ------ */
  // 節點取自登記表；沒有座標的（理論上沒有）跳過。
  const nodes = Object.values(MAP_REGISTRY).filter(m => m.x != null && m.z != null);

  function layout(w, h) {
    const PAD = 70;
    let x0 = Infinity, x1 = -Infinity, z0 = Infinity, z1 = -Infinity;
    for (const n of nodes) {
      x0 = Math.min(x0, n.x); x1 = Math.max(x1, n.x);
      z0 = Math.min(z0, n.z); z1 = Math.max(z1, n.z);
    }
    const s = Math.min((w - PAD * 2) / (x1 - x0), (h - PAD * 2) / (z1 - z0));
    const ox = (w - (x1 - x0) * s) / 2, oz = (h - (z1 - z0) * s) / 2;
    const pt = {};
    for (const n of nodes) pt[n.id] = [ox + (n.x - x0) * s, oz + (n.z - z0) * s];
    return pt;
  }

  /* ------------------------------------------------ 繪製 ------ */
  function draw() {
    const w = Math.min(innerWidth - 80, 980);
    const h = Math.min(innerHeight - 80, 700);
    const dpr = Math.min(devicePixelRatio, 2);
    canvas.width = w * dpr; canvas.height = h * dpr;
    canvas.style.width = `${w}px`; canvas.style.height = `${h}px`;
    const g = canvas.getContext('2d');
    g.scale(dpr, dpr);
    const rand = lcg(20260801);

    // --- 紙 ---
    g.fillStyle = '#e7dcc2';
    g.fillRect(0, 0, w, h);
    for (let i = 0; i < 900; i++) {           // 纖維斑點
      g.fillStyle = `rgba(${150 + rand() * 60},${130 + rand() * 50},${95 + rand() * 40},${rand() * 0.08})`;
      g.beginPath();
      g.arc(rand() * w, rand() * h, 0.6 + rand() * 2.2, 0, 7);
      g.fill();
    }
    // 邊緣做舊（暈影）
    const vg = g.createRadialGradient(w / 2, h / 2, Math.min(w, h) * 0.36, w / 2, h / 2, Math.max(w, h) * 0.72);
    vg.addColorStop(0, 'rgba(90,66,40,0)');
    vg.addColorStop(1, 'rgba(90,66,40,0.30)');
    g.fillStyle = vg;
    g.fillRect(0, 0, w, h);

    const pt = layout(w, h);
    const INK = '#4a3626', FADE = 'rgba(74,54,38,.42)', RED = '#b03a2e';

    // --- 連線（墨線，手抖一小段折線） ---
    const drawn = new Set();
    g.lineCap = 'round';
    for (const n of nodes) {
      for (const to of n.connections) {
        const key = [n.id, to].sort().join('>');
        if (drawn.has(key) || !pt[to]) continue;
        drawn.add(key);
        const [ax, ay] = pt[n.id], [bx, by] = pt[to];
        const open = n.built && MAP_REGISTRY[to].built;
        g.strokeStyle = open ? INK : FADE;
        g.lineWidth = open ? 2 : 1.4;
        g.setLineDash(open ? [] : [5, 5]);
        // 中點加一點垂直偏移 —— 直尺畫的線沒有手繪感
        const mx = (ax + bx) / 2, my = (ay + by) / 2;
        const dx = bx - ax, dy = by - ay;
        const len = Math.hypot(dx, dy) || 1;
        const off = (rand() - 0.5) * Math.min(14, len * 0.12);
        g.beginPath();
        g.moveTo(ax, ay);
        g.quadraticCurveTo(mx - dy / len * off, my + dx / len * off, bx, by);
        g.stroke();
      }
    }
    g.setLineDash([]);

    // --- 節點 ---
    g.textAlign = 'center';
    for (const n of nodes) {
      const [x, y] = pt[n.id];
      const isCur = n.id === current;
      const eventOnly = n.connections.length === 0;
      if (n.built) {
        g.fillStyle = isCur ? RED : INK;
        g.beginPath();
        g.arc(x, y, isCur ? 6 : 4.5, 0, 7);
        g.fill();
        if (isCur) {                              // 現在地：硃砂雙圈
          g.strokeStyle = RED;
          g.lineWidth = 1.6;
          g.beginPath(); g.arc(x, y, 10.5, 0, 7); g.stroke();
        }
      } else {
        g.strokeStyle = FADE;
        g.lineWidth = 1.4;
        g.setLineDash([3.5, 3.5]);
        g.beginPath(); g.arc(x, y, 7.5, 0, 7); g.stroke();
        g.setLineDash([]);
        g.fillStyle = FADE;
        g.font = '700 10px "Noto Sans TC","Microsoft JhengHei",sans-serif';
        g.fillText('？', x, y + 3.5);
      }
      // 名字：建成 = 墨色；未建 = 淡墨＋（未開放）；事件圖 = 再淡一階
      const faded = !n.built || eventOnly;
      g.fillStyle = isCur ? RED : (faded ? FADE : INK);
      g.font = `${isCur ? 700 : 500} 13px "Noto Sans TC","Microsoft JhengHei",sans-serif`;
      g.fillText(n.zh, x, y - 13);
      if (!n.built) {
        g.font = '400 9px "Noto Sans TC","Microsoft JhengHei",sans-serif';
        g.fillText(eventOnly ? '（事件）' : '（未開放）', x, y + 21);
      } else if (isCur) {
        g.font = '700 9px "Noto Sans TC","Microsoft JhengHei",sans-serif';
        g.fillText('現在地', x, y + 22);
      }
    }

    // --- 題字與方位 ---
    g.textAlign = 'left';
    g.fillStyle = INK;
    g.font = '600 22px "Noto Sans TC","Microsoft JhengHei",serif';
    g.fillText('幻 想 鄉', 26, 42);
    g.font = '400 10px sans-serif';
    g.fillStyle = FADE;
    g.fillText('GENSOKYO', 27, 56);
    // 方位標（北在上）
    g.textAlign = 'center';
    g.fillStyle = INK;
    g.font = '600 13px "Noto Sans TC",serif';
    g.fillText('北', w - 36, 34);
    g.strokeStyle = INK; g.lineWidth = 1.4;
    g.beginPath();
    g.moveTo(w - 36, 58); g.lineTo(w - 36, 40);
    g.moveTo(w - 40, 46); g.lineTo(w - 36, 40); g.lineTo(w - 32, 46);
    g.stroke();
  }

  /* ------------------------------------------------ 開關 ------ */
  const open = () => { state.isOpen = true; wrap.classList.add('on'); draw(); };
  const close = () => { state.isOpen = false; wrap.classList.remove('on'); };

  window.addEventListener('keydown', (e) => {
    if (e.code === 'KeyM') {
      if (state.isOpen) { close(); return; }
      if (isBlocked()) return;
      open();
    }
  });
  // ESC 關地圖時不能讓 ESC 選單也開 —— 用捕獲階段先攔下來
  window.addEventListener('keydown', (e) => {
    if (e.code === 'Escape' && state.isOpen) {
      close();
      e.stopImmediatePropagation();
    }
  }, true);
  addEventListener('resize', () => { if (state.isOpen) draw(); });

  return { get isOpen() { return state.isOpen; }, open, close };
}
