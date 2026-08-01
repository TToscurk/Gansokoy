// 小地圖 —— 右上角常駐的本圖俯視簡圖，全地圖共用。
//
// 底圖（路網、傳送點、邊界）在建構時畫一次進離屏 canvas，每幀只把
// 底圖貼上來再畫一個玩家箭頭 —— 不要每幀重繪整張。
//
// 路網直接吃 PathNet 的 samples（每張圖建路時本來就有），沒有路網的
// 圖（神社、永遠亭）就只畫傳送點與邊界。N 鍵開關，記在 localStorage。
//
// 座標約定跟世界一致：+X 東（畫面右）、-Z 北（畫面上）。

const CSS = `
#minimap { position:fixed; right:18px; top:150px; z-index:12;
  border:1px solid rgba(217,178,106,.30); border-radius:4px;
  background:rgba(14,12,18,.55); box-shadow:0 8px 26px rgba(0,0,0,.4);
  pointer-events:none; }
#minimap.off { display:none; }
`;

const LS_KEY = 'gansokoy:minimap';

/**
 * @param {object} o
 * @param {{minX:number,maxX:number,minZ:number,maxZ:number}} o.bounds 遊玩範圍
 * @param {{samples:{x:number,z:number}[]}} [o.paths]  PathNet（有就畫路網）
 * @param {[number,number][][]} [o.lines]  額外的折線（沒有 PathNet 的圖用，世界座標）
 * @param {{x:number,z:number,label:string,color?:string}[]} [o.portals] 傳送點
 * @param {() => {x:number,z:number}} o.getPos  玩家位置
 * @param {() => number} o.getYaw  玩家朝向（controller 的 yaw：0 = 面向 -Z 北）
 * @param {number} [o.size=148]  畫布邊長上限（依地圖長寬比縮）
 */
export function installMinimap({ bounds, paths = null, lines = [], portals = [], getPos, getYaw, size = 148 }) {
  const style = document.createElement('style');
  style.textContent = CSS;
  document.head.appendChild(style);

  const spanX = bounds.maxX - bounds.minX, spanZ = bounds.maxZ - bounds.minZ;
  const s = size / Math.max(spanX, spanZ);
  const w = Math.max(64, Math.round(spanX * s)), h = Math.max(64, Math.round(spanZ * s));
  const PAD = 7;
  const dpr = Math.min(devicePixelRatio, 2);

  const canvas = document.createElement('canvas');
  canvas.id = 'minimap';
  canvas.width = (w + PAD * 2) * dpr; canvas.height = (h + PAD * 2) * dpr;
  canvas.style.width = `${w + PAD * 2}px`; canvas.style.height = `${h + PAD * 2}px`;
  document.body.appendChild(canvas);
  const g = canvas.getContext('2d');
  g.scale(dpr, dpr);

  const px = (x) => PAD + (x - bounds.minX) * (w / spanX);
  const pz = (z) => PAD + (z - bounds.minZ) * (h / spanZ);

  /* ------------------------------------------ 靜態底圖（畫一次） ------ */
  const base = document.createElement('canvas');
  base.width = canvas.width; base.height = canvas.height;
  {
    const b = base.getContext('2d');
    b.scale(dpr, dpr);
    // 邊界框（虛線 —— 提醒「這張圖就這麼大」）
    b.strokeStyle = 'rgba(217,178,106,.25)';
    b.lineWidth = 1;
    b.setLineDash([3, 3]);
    b.strokeRect(PAD, PAD, w, h);
    b.setLineDash([]);
    // 路網：samples 直接點上去（間距近，讀起來就是線）
    if (paths?.samples?.length) {
      b.fillStyle = 'rgba(214,186,140,.75)';
      for (const p of paths.samples) {
        b.fillRect(px(p.x) - 0.7, pz(p.z) - 0.7, 1.4, 1.4);
      }
    }
    // 額外折線（沒有 PathNet 的圖：街道、參道）
    b.strokeStyle = 'rgba(214,186,140,.7)';
    b.lineWidth = 1.6;
    b.lineCap = 'round';
    for (const line of lines) {
      b.beginPath();
      line.forEach(([x, z], i) => (i ? b.lineTo(px(x), pz(z)) : b.moveTo(px(x), pz(z))));
      b.stroke();
    }
    // 傳送點：光點色的小圈＋目的地名
    for (const p of portals) {
      const c = p.color ?? '#8be8ff';
      b.fillStyle = c;
      b.beginPath();
      b.arc(px(p.x), pz(p.z), 2.6, 0, 7);
      b.fill();
      b.font = '600 8.5px "Noto Sans TC","Microsoft JhengHei",sans-serif';
      b.fillStyle = 'rgba(240,230,210,.92)';
      b.textAlign = 'center';
      // 名字往圖內推，不出框
      const tx = Math.min(Math.max(px(p.x), 16), w + PAD * 2 - 16);
      const ty = pz(p.z) < (h + PAD * 2) / 2 ? pz(p.z) + 11 : pz(p.z) - 6;
      b.fillText(p.label, tx, ty);
    }
  }

  /* ------------------------------------------------ 每幀更新 ------ */
  let visible = true;
  try { visible = localStorage.getItem(LS_KEY) !== '0'; } catch { /* 私隱模式 */ }
  canvas.classList.toggle('off', !visible);

  function update() {
    if (!visible) return;
    g.clearRect(0, 0, w + PAD * 2, h + PAD * 2);
    g.drawImage(base, 0, 0, w + PAD * 2, h + PAD * 2);
    // 神社在選角前 ctrl 是 null —— 沒有玩家就只畫底圖，
    // 千萬別 throw：tick 裡丟例外會讓整個渲染迴圈斷掉。
    const p = getPos?.();
    if (!p) return;
    const x = px(p.x), y = pz(p.z);
    // 玩家箭頭。controller 的 yaw 口徑：0 = 面向 +Z（南）、π/2 = +X（東）
    // —— 面向向量是 (sin yaw, cos yaw)。畫面上北(-Z)在上，箭頭素體朝上，
    // 轉到面向向量的螢幕角就是 π - yaw。
    g.save();
    g.translate(x, y);
    g.rotate(Math.PI - getYaw());
    g.fillStyle = '#ff8a6b';
    g.beginPath();
    g.moveTo(0, -5); g.lineTo(3.6, 4); g.lineTo(0, 2.2); g.lineTo(-3.6, 4);
    g.closePath();
    g.fill();
    g.restore();
  }

  window.addEventListener('keydown', (e) => {
    if (e.code !== 'KeyN') return;
    visible = !visible;
    canvas.classList.toggle('off', !visible);
    try { localStorage.setItem(LS_KEY, visible ? '1' : '0'); } catch { /* 私隱模式 */ }
  });

  return { update, get visible() { return visible; } };
}
