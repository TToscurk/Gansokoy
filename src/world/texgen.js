// 從既有的 canvas 貼圖自動生成法線貼圖與粗糙度貼圖
// （材質與畫質升級書・第 1 章）。
//
// 為什麼要有這個檔案：專案已經有一整套程序化 canvas 貼圖（TEX.wood /
// stone / masonry / roof / lacquer…），但每個表面只有 `map` 一張，
// 所以木頭沒有木紋的起伏、石牆沒有磚縫的深度 —— 表面平滑得像貼紙。
// 補法線貼圖通常要下載外部資產，那會破壞這個專案「純瀏覽器生成、
// 離線可跑」的原則。
//
// 這裡的做法不下載任何東西：**把既有貼圖的明暗當成高度場**。
// 畫木紋時那些深色線條本來就是「凹進去的紋路」，畫磚縫時那條暗線本來
// 就是「縫」—— 亮度早就編碼了高度資訊，只是以前沒人拿來用。用 Sobel
// 算子對亮度求斜率，就能還原出法線；同一份亮度重新映射一次，就是
// 粗糙度（暗處＝縫隙／磨損＝比較粗）。
//
// 成本：一張 256² 的貼圖多算兩張同尺寸的 canvas，都在載入時做完，
// 執行期零成本。VRAM 則是一張變三張 —— 呼叫端請顧一下
// `renderer.info.memory.textures`。

import * as THREE from 'three';

/** 感知亮度（跟後製那支 grade shader 用同一組係數） */
const LUMA = (r, g, b) => (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;

/**
 * 讀出 canvas 的亮度場。回傳 0~1 的 Float32Array，長度 w*h。
 * @param {HTMLCanvasElement} canvas
 */
function heightField(canvas) {
  const w = canvas.width, h = canvas.height;
  const d = canvas.getContext('2d', { willReadFrequently: true })
    .getImageData(0, 0, w, h).data;
  const out = new Float32Array(w * h);
  for (let i = 0, p = 0; i < out.length; i++, p += 4) {
    out[i] = LUMA(d[p], d[p + 1], d[p + 2]);
  }
  return { w, h, data: out };
}

/**
 * 把一張 canvas 的亮度當高度場，用 Sobel 算子求出法線貼圖。
 *
 * 取樣座標一律取模（wrap）而不是夾邊（clamp）—— 這些貼圖全都是
 * RepeatWrapping 平鋪的，夾邊會在拼接處留下一圈假的稜線。
 *
 * @param {HTMLCanvasElement} canvas 來源（通常是 CanvasTexture 的 .image）
 * @param {number} [strength=1] 起伏強度。太大會變成浮雕，1 附近最自然。
 * @returns {THREE.CanvasTexture} 切線空間法線貼圖（線性色彩空間）
 */
export function normalFromCanvas(canvas, strength = 1) {
  const { w, h, data } = heightField(canvas);
  const at = (x, y) => data[((y % h) + h) % h * w + (((x % w) + w) % w)];

  const dst = document.createElement('canvas');
  dst.width = w; dst.height = h;
  const ctx = dst.getContext('2d');
  const img = ctx.createImageData(w, h);
  const o = img.data;

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      // Sobel：左右／上下各三個取樣，中間權重加倍
      const tl = at(x - 1, y - 1), t = at(x, y - 1), tr = at(x + 1, y - 1);
      const l = at(x - 1, y), r = at(x + 1, y);
      const bl = at(x - 1, y + 1), b = at(x, y + 1), br = at(x + 1, y + 1);
      const dx = (tr + 2 * r + br) - (tl + 2 * l + bl);
      const dy = (bl + 2 * b + br) - (tl + 2 * t + tr);

      // 亮＝高，所以斜率要取負才會朝外凸
      let nx = -dx * strength, ny = -dy * strength, nz = 1;
      const len = Math.hypot(nx, ny, nz) || 1;
      nx /= len; ny /= len; nz /= len;

      const p = (y * w + x) * 4;
      o[p]     = (nx * 0.5 + 0.5) * 255;
      o[p + 1] = (ny * 0.5 + 0.5) * 255;
      o[p + 2] = (nz * 0.5 + 0.5) * 255;
      o[p + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);

  const tex = new THREE.CanvasTexture(dst);
  // 法線貼圖是資料不是顏色 —— 千萬不能標成 sRGB，否則會被再解碼一次
  tex.colorSpace = THREE.NoColorSpace;
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  return tex;
}

/**
 * 把亮度重新映射成粗糙度貼圖。
 *
 * 預設 invert=true：**暗處比較粗**。木頭的深色紋理是凹進去的纖維、
 * 石頭的暗斑是磨損，這些地方本來就不該反光；亮的地方（磨平的表面、
 * 受光的凸起）比較滑。少數材質相反（例如漆器的裂紋是亮的），
 * 那時候把 invert 關掉。
 *
 * @param {HTMLCanvasElement} canvas
 * @param {object} [o]
 * @param {number} [o.min=0.6] 最滑處的粗糙度
 * @param {number} [o.max=0.95] 最粗處的粗糙度
 * @param {boolean} [o.invert=true] 暗處是否比較粗
 * @returns {THREE.CanvasTexture} 灰階粗糙度貼圖（線性色彩空間）
 */
export function roughnessFromCanvas(canvas, { min = 0.6, max = 0.95, invert = true } = {}) {
  const { w, h, data } = heightField(canvas);
  const dst = document.createElement('canvas');
  dst.width = w; dst.height = h;
  const ctx = dst.getContext('2d');
  const img = ctx.createImageData(w, h);
  const o = img.data;

  for (let i = 0, p = 0; i < data.length; i++, p += 4) {
    const t = invert ? 1 - data[i] : data[i];
    const v = Math.round(Math.max(0, Math.min(1, min + (max - min) * t)) * 255);
    o[p] = o[p + 1] = o[p + 2] = v;
    o[p + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);

  const tex = new THREE.CanvasTexture(dst);
  tex.colorSpace = THREE.NoColorSpace;
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  return tex;
}

/**
 * 從一張既有的 CanvasTexture 長出整組 PBR 貼圖。
 *
 * 直接吃已經做好的 texture（`CanvasTexture.image` 就是原本那張 canvas），
 * 所以呼叫端不必把每個 draw 函式重新拆出來 —— 既有的 `TEX.wood(1,2)`
 * 那種寫法原封不動就能升級。repeat / anisotropy / wrap 會一起複製過去，
 * 三張貼圖的 UV 必須完全一致，錯開一格就會出現「紋路對不上凹凸」。
 *
 * @param {THREE.CanvasTexture} tex 既有的顏色貼圖
 * @param {object} [o]
 * @param {number} [o.normalStrength=1]
 * @param {[number,number]} [o.roughRange=[0.6,0.95]]
 * @param {boolean} [o.roughInvert=true]
 * @returns {{map:THREE.Texture, normalMap:THREE.Texture, roughnessMap:THREE.Texture, normalScale:THREE.Vector2}}
 *          直接展開進 MeshStandardMaterial 的參數即可。
 */
export function mapsFromTexture(tex, {
  normalStrength = 1, roughRange = [0.6, 0.95], roughInvert = true,
} = {}) {
  const canvas = tex.image;
  const normalMap = cachedNormal(tex, normalStrength);
  const roughnessMap = roughnessFromCanvas(canvas, {
    min: roughRange[0], max: roughRange[1], invert: roughInvert,
  });
  for (const t of [normalMap, roughnessMap]) {
    t.wrapS = tex.wrapS; t.wrapT = tex.wrapT;
    t.repeat.copy(tex.repeat);
    t.offset.copy(tex.offset);
    t.anisotropy = tex.anisotropy;
  }
  return { map: tex, normalMap, roughnessMap };
}

/* ─────────────────────────────────────── 給各張地圖共用的薄包裝 ── */

/**
 * 法線強度。`?nstr=1.5` 可以現場換，不必改代碼 —— 升級書 §5 規定的 A/B
 * 流程要靠它。八張圖讀同一個查詢參數，不然比 A/B 時各圖強度會對不上。
 */
export const NORMAL_STRENGTH = (() => {
  const v = parseFloat(new URLSearchParams(location.search).get('nstr'));
  return Number.isFinite(v) && v >= 0 ? v : 1.0;
})();

let _roughMade = 0;

/* 同一張貼圖常常被兩個材質共用（例如里的 wood 與 darkWood 只差顏色），
 * 法線只跟來源與強度有關，重算一次就白白多一張 GPU 貼圖。粗糙度不快取 ——
 * 它的範圍是各材質自己的。
 *
 * 鍵用 texture 物件而不是底下的 canvas：同一張 canvas 有可能被兩個 repeat
 * 不同的 CanvasTexture 包起來，共用法線會被後者的 repeat 覆寫掉。 */
const _normalCache = new WeakMap();
let _normalsMade = 0;
function cachedNormal(tex, strength) {
  let byStrength = _normalCache.get(tex);
  if (!byStrength) _normalCache.set(tex, byStrength = new Map());
  if (!byStrength.has(strength)) {
    byStrength.set(strength, normalFromCanvas(tex.image, strength));
    _normalsMade++;
  }
  return byStrength.get(strength);
}

/**
 * `...texMaps(someCanvasTexture, [0.72, 0.95])` 展開進 MeshStandardMaterial。
 *
 * **roughness 純量記得一起設成 1**：有了 roughnessMap 之後兩者是相乘的，
 * 純量留在原本的 0.9 會把整體再壓暗一階。roughRange 則以原本那個純量為
 * 中心往兩邊開，例如 0.95 → [0.86, 1.0]。
 */
export function texMaps(tex, roughRange, o = {}) {
  _roughMade++;
  return mapsFromTexture(tex, { normalStrength: NORMAL_STRENGTH, roughRange, ...o });
}

/** 這張圖實際生成了幾張資料貼圖（法線會共用，所以不是材質數 × 2）。 */
export const texgenCount = () => _normalsMade + _roughMade;
