// 程序化 noise 工具箱（材質與畫質升級書・第 2 章）
//
// 為什麼需要這個檔案：既有的 `noise(ctx, size, amount, alpha)` 是逐像素
// 白噪音 —— 每個像素跟鄰居完全無關，所以放大看是「顆粒」不是「材質」。
// 真實表面的起伏是有尺度的：木紋有粗有細、石頭有大斑塊也有小麻點。
// 那叫 fBm（fractional Brownian motion）—— 把同一種 noise 用不同頻率
// 疊好幾層，每層振幅減半。這也是第 3 章 triplanar 混材質要用的東西。
//
// 全部平鋪安全（tileable）：這些貼圖都是 RepeatWrapping，任何一格對不上
// 都會在畫面上排出一整排接縫。value noise 的格點座標一律對 period 取模，
// Worley 的特徵點也是，所以左邊界跟右邊界永遠算出同一個值。
//
// 成本：都在載入時算完，執行期零成本。

/* ─────────────────────────────────────────────────────────── 亂數 ── */

/**
 * 決定性亂數。`Math.random()` 不能用 —— 同一份代碼每次載入畫出不同的
 * 貼圖，A/B 比對就沒有意義了（專案其他地方用 LCG 也是同一個理由）。
 * @param {number} seed
 * @returns {() => number} 0~1
 */
export function rng(seed = 1) {
  let s = (seed >>> 0) || 1;
  return () => {
    // xorshift32
    s ^= s << 13; s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5; s >>>= 0;
    return s / 4294967296;
  };
}

/** 格點雜湊。同樣的 (x, y, seed) 永遠得到同一個 0~1。 */
function hash2(x, y, seed) {
  // 位移一律用 >>> —— 帶號的 >> 會把符號位灌進 bit31，XOR 之後 bit31
  // 永遠變 0，整個雜湊的值域就只剩 0~0.5（實測平均 0.25）。
  let h = (x * 374761393 + y * 668265263 + seed * 1274126177) >>> 0;
  h = (h ^ (h >>> 13)) >>> 0;
  h = Math.imul(h, 1274126177) >>> 0;
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

/** period 可能是數字也可能是 [px, py]，兩種都要能乘。 */
const scalePeriod = (p, k) => (Array.isArray(p) ? [p[0] * k, p[1] * k] : p * k);

/** 5 次平滑（smootherstep）—— 三次的一階導數在格點上不連續，會留下格狀感。 */
const fade = (t) => t * t * t * (t * (t * 6 - 15) + 10);

/* ───────────────────────────────────────────────────── value noise ── */

/**
 * 可平鋪的 value noise。
 *
 * period 可以給一個數字，也可以給 `[px, py]` 兩軸不同 —— 木紋要沿纖維
 * 方向拉長、瓦楞要橫向延伸，那是把某一軸的週期壓到很小做出來的。
 *
 * @param {number} x @param {number} y  取樣座標（單位＝格）
 * @param {number|[number,number]} period 幾格之後重複（貼圖寬度 / 格寬）
 * @param {number} seed
 * @returns {number} 0~1
 */
export function valueNoise(x, y, period, seed = 0) {
  const px = Array.isArray(period) ? period[0] : period;
  const py = Array.isArray(period) ? period[1] : period;
  const xi = Math.floor(x), yi = Math.floor(y);
  const xf = x - xi, yf = y - yi;
  const mx = (v) => ((v % px) + px) % px;   // 取模才平鋪得起來
  const my = (v) => ((v % py) + py) % py;
  const x0 = mx(xi), x1 = mx(xi + 1), y0 = my(yi), y1 = my(yi + 1);

  const a = hash2(x0, y0, seed), b = hash2(x1, y0, seed);
  const c = hash2(x0, y1, seed), d = hash2(x1, y1, seed);
  const u = fade(xf), v = fade(yf);
  return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v;
}

/**
 * fBm：多層八度疊加。octaves 越多細節越豐富但也越花時間。
 *
 * @param {number} x @param {number} y
 * @param {object} [o]
 * @param {number} [o.period=8]      第一層的重複週期
 * @param {number} [o.octaves=4]
 * @param {number} [o.gain=0.5]      每層振幅的衰減
 * @param {number} [o.lacunarity=2]  每層頻率的倍率
 * @param {number} [o.seed=0]
 * @returns {number} 0~1（已正規化，總振幅固定）
 */
export function fbm(x, y, {
  period = 8, octaves = 4, gain = 0.5, lacunarity = 2, seed = 0,
} = {}) {
  let sum = 0, amp = 1, norm = 0, f = 1, p = period;
  for (let i = 0; i < octaves; i++) {
    sum += amp * valueNoise(x * f, y * f, p, seed + i * 131);
    norm += amp;
    // period 要跟著頻率一起放大，否則高頻層的取模週期對不上，接縫會回來
    amp *= gain; f *= lacunarity; p = scalePeriod(p, lacunarity);
  }
  return sum / norm;
}

/**
 * 脊狀 fBm。把 noise 摺起來取絕對值的補數 —— 峰是尖的、谷是圓的，
 * 木頭年輪與岩石稜線都是這個形狀，一般 fBm 太「棉花」做不出來。
 * @returns {number} 0~1
 */
export function ridged(x, y, o = {}) {
  const { octaves = 4, gain = 0.5, lacunarity = 2, period = 8, seed = 0 } = o;
  let sum = 0, amp = 1, norm = 0, f = 1, p = period;
  for (let i = 0; i < octaves; i++) {
    const n = 1 - Math.abs(valueNoise(x * f, y * f, p, seed + i * 131) * 2 - 1);
    sum += amp * n * n;
    norm += amp;
    amp *= gain; f *= lacunarity; p = scalePeriod(p, lacunarity);
  }
  return sum / norm;
}

/* ───────────────────────────────────────────────────────── Worley ── */

/**
 * 可平鋪的 Worley（細胞）噪音 —— 到最近特徵點的距離。
 * 石頭的顆粒、砂礫、皮革的紋路都是這個形狀，fBm 做不出「一顆一顆」。
 *
 * @param {number} x @param {number} y 取樣座標（單位＝格）
 * @param {number} period 幾格之後重複
 * @param {number} [seed=0]
 * @returns {number} 0~1，0 在特徵點正中心
 */
export function worley(x, y, period, seed = 0) {
  const xi = Math.floor(x), yi = Math.floor(y);
  let best = 8;
  for (let dy = -1; dy <= 1; dy++) {
    for (let dx = -1; dx <= 1; dx++) {
      const cx = xi + dx, cy = yi + dy;
      // 特徵點的位置由「取模後的格座標」決定，跨越邊界時才對得上
      const mx = ((cx % period) + period) % period;
      const my = ((cy % period) + period) % period;
      const px = cx + hash2(mx, my, seed);
      const py = cy + hash2(mx, my, seed + 7919);
      const d = Math.hypot(px - x, py - y);
      if (d < best) best = d;
    }
  }
  return Math.min(1, best);
}

/* ─────────────────────────────────────────── 畫到 canvas 的薄包裝 ── */

/**
 * 逐像素跑一個函式，結果乘進既有的畫面（multiply）。
 *
 * 乘法而不是覆蓋：呼叫端已經用 2D API 畫好了色塊、磚縫、年輪那些
 * 「結構」，這一層要做的是在上面疊明暗變化，不該把結構蓋掉。
 *
 * `step > 1` 時只在粗網格上算 f，中間用雙線性補回來。fBm 是連續函式，
 * 512² 全解析度逐點算是浪費 —— 實測 step 2 就少掉四分之三的呼叫，
 * 而最高頻的那一層八度在 512 上也還有十幾像素寬，補出來看不出差別。
 * 銳利的東西（磚縫、蓆緣）本來就是用 2D API 畫的，不走這條路。
 *
 * @param {CanvasRenderingContext2D} g
 * @param {number} size
 * @param {(x:number, y:number) => number} f 回傳 0~2 的倍率（1 ＝不變）
 * @param {object} [o]
 * @param {number} [o.step=1] 取樣間隔，2 或 4 可以大幅省時間
 */
export function modulate(g, size, f, { step = 1 } = {}) {
  const img = g.getImageData(0, 0, size, size);
  const d = img.data;
  const put = (i, k) => {
    d[i] = Math.max(0, Math.min(255, d[i] * k));
    d[i + 1] = Math.max(0, Math.min(255, d[i + 1] * k));
    d[i + 2] = Math.max(0, Math.min(255, d[i + 2] * k));
  };

  if (step <= 1) {
    for (let y = 0, i = 0; y < size; y++) {
      for (let x = 0; x < size; x++, i += 4) put(i, f(x, y));
    }
    g.putImageData(img, 0, 0);
    return;
  }

  // 粗網格。最後一排／一列直接取樣 size（＝下一塊的 0），
  // 這樣補間到邊界時左右接得起來，不會在平鋪處留一條縫。
  const n = Math.ceil(size / step) + 1;
  const grid = new Float32Array(n * n);
  for (let gy = 0; gy < n; gy++) {
    for (let gx = 0; gx < n; gx++) grid[gy * n + gx] = f(gx * step, gy * step);
  }
  for (let y = 0, i = 0; y < size; y++) {
    const fy = y / step, y0 = fy | 0, ty = fy - y0;
    for (let x = 0; x < size; x++, i += 4) {
      const fx = x / step, x0 = fx | 0, tx = fx - x0;
      const a = grid[y0 * n + x0], b = grid[y0 * n + x0 + 1];
      const c = grid[(y0 + 1) * n + x0], e = grid[(y0 + 1) * n + x0 + 1];
      put(i, (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + e * tx) * ty);
    }
  }
  g.putImageData(img, 0, 0);
}

/**
 * fBm 明暗層。`grain(g, s, { scale: 6, strength: 0.25 })` 就是
 * 「以 6 格為單位的斑駁，最亮最暗差 ±25%」。
 *
 * 這是取代舊 `noise(ctx, size, amount)` 的主力 —— 舊的是白噪音，
 * 放大只會看到砂糖；這個有尺度，看起來才像表面。
 */
export function grain(g, size, {
  scale = 8, strength = 0.2, octaves = 4, seed = 1, ridge = false,
} = {}) {
  const fn = ridge ? ridged : fbm;
  const k = scale / size;
  modulate(g, size, (x, y) =>
    1 + (fn(x * k, y * k, { period: scale, octaves, seed }) - 0.5) * 2 * strength);
}
