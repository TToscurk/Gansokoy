// 路網 —— 一組會分岔的路徑中心線，以及「離最近的路多遠」的查詢。
//
// 為什麼需要這個：一條筆直或單純的路，地形高度用一條公式就能寫
// （獸道舊版是 `|x| < 7 ? 0 : (|x|-7)²`）。但只要路開始蜿蜒、開始分岔，
// 「離路多遠」就不再有封閉解 —— 而地形、路面幾何、樹木佈點、怪物避讓
// 全都要問這個問題。這裡把它做成一次算好、之後 O(1) 查詢的東西。
//
// 效能：heightAt() 是每幀被呼叫幾百次的函式（玩家、怪物、地形取樣），
// 不能每次都掃過幾百個取樣點。所以取樣點會先塞進格線，查詢只看鄰近的
// 九宮格 —— 實際上每次只算幾個點的距離。

/**
 * @param {{pts:[number,number][], width?:number, id?:string}[]} segments
 *        每段的中心線控制點（世界座標）。點與點之間會自動細分。
 * @param {object} [opts]
 * @param {number} [opts.step=3]  中心線的取樣間距（公尺）
 * @param {number} [opts.cell=12] 格線邊長（公尺）
 */
export class PathNet {
  constructor(segments, { step = 3, cell = 12 } = {}) {
    this.cell = cell;
    this.segments = segments;
    this.samples = [];        // {x, z, w, seg, t}
    this.grid = new Map();    // "cx,cz" → 樣點索引陣列

    segments.forEach((seg, si) => {
      const pts = seg.pts;
      const w = seg.width ?? 6;
      // 控制點之間用 Catmull-Rom 細分，轉彎才圓順（折線會看出角）
      const dense = catmullRom(pts, step);
      dense.forEach((p, i) => {
        this.samples.push({ x: p[0], z: p[1], w, seg: si, t: i / (dense.length - 1) });
      });
    });

    this.samples.forEach((s, i) => {
      const k = this._key(s.x, s.z);
      if (!this.grid.has(k)) this.grid.set(k, []);
      this.grid.get(k).push(i);
    });
  }

  _key(x, z) {
    return `${Math.floor(x / this.cell)},${Math.floor(z / this.cell)}`;
  }

  /**
   * 離最近的中心線多遠（公尺）。查不到鄰近樣點時回 Infinity ——
   * 呼叫端可以據此判斷「這裡遠離所有路」。
   * @param {number} [reach=2] 往外找幾圈格子。路寬或格線變大時要跟著加。
   */
  dist(x, z, reach = 2) {
    let best = Infinity;
    const cx = Math.floor(x / this.cell), cz = Math.floor(z / this.cell);
    for (let i = -reach; i <= reach; i++) {
      for (let j = -reach; j <= reach; j++) {
        const list = this.grid.get(`${cx + i},${cz + j}`);
        if (!list) continue;
        for (const idx of list) {
          const s = this.samples[idx];
          const d = Math.hypot(s.x - x, s.z - z);
          if (d < best) best = d;
        }
      }
    }
    return best;
  }

  /** 扣掉路寬之後還剩多遠（在路面上時是 0）—— 地形抬升直接吃這個值 */
  edgeDist(x, z, reach = 2) {
    let best = Infinity;
    const cx = Math.floor(x / this.cell), cz = Math.floor(z / this.cell);
    for (let i = -reach; i <= reach; i++) {
      for (let j = -reach; j <= reach; j++) {
        const list = this.grid.get(`${cx + i},${cz + j}`);
        if (!list) continue;
        for (const idx of list) {
          const s = this.samples[idx];
          const d = Math.hypot(s.x - x, s.z - z) - s.w / 2;
          if (d < best) best = d;
        }
      }
    }
    return Math.max(0, best === Infinity ? Infinity : best);
  }

  /** 某一段的細分點（路面幾何要用） */
  densePoints(segIndex, step = 3) {
    return catmullRom(this.segments[segIndex].pts, step);
  }
}

/**
 * Catmull-Rom 細分。折線直接拿來鋪路會在控制點看出明顯的角，
 * 過一次樣條之後轉彎才是圓的。
 * @param {[number,number][]} pts
 * @param {number} step 目標間距（公尺）
 * @returns {[number,number][]}
 */
export function catmullRom(pts, step = 3) {
  if (pts.length < 2) return pts.slice();
  // 頭尾各複製一份當控制點，端點才不會被切掉
  const p = [pts[0], ...pts, pts[pts.length - 1]];
  const out = [];
  for (let i = 1; i < p.length - 2; i++) {
    const [x0, z0] = p[i - 1], [x1, z1] = p[i], [x2, z2] = p[i + 1], [x3, z3] = p[i + 2];
    const segLen = Math.hypot(x2 - x1, z2 - z1);
    const n = Math.max(2, Math.ceil(segLen / step));
    for (let k = 0; k < n; k++) {
      const t = k / n, t2 = t * t, t3 = t2 * t;
      out.push([
        0.5 * ((2 * x1) + (-x0 + x2) * t + (2 * x0 - 5 * x1 + 4 * x2 - x3) * t2 + (-x0 + 3 * x1 - 3 * x2 + x3) * t3),
        0.5 * ((2 * z1) + (-z0 + z2) * t + (2 * z0 - 5 * z1 + 4 * z2 - z3) * t2 + (-z0 + 3 * z1 - 3 * z2 + z3) * t3),
      ]);
    }
  }
  out.push(pts[pts.length - 1]);
  return out;
}
