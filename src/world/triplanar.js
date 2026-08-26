// 地形三平面貼圖（材質與畫質升級書・第 3 章）
//
// 問題：地面是 PlaneGeometry 位移出來的高度場，UV 是從正上方投影下來的。
// 平地沒事，陡坡上一格 UV 要拉過好幾公尺的斜面 —— 貼圖就糊成一條一條。
// 這是畫面佔比最大的一塊，糊在這裡最傷。
//
// 做法：不用 UV，改用**世界座標**當貼圖座標，從三個軸向各採樣一次
// （XY / ZY / XZ），再依表面法線的三個分量當權重混合。陡坡自然由
// 側面那兩張主導，永遠不會拉伸。
//
// 另外依坡度混第二套材質（岩石）：平的地方是草，陡的地方自動露岩。
// 這比用頂點色手刷可靠 —— 地形改了不用重刷。
//
// 成本：每個像素採樣三次（色彩＋法線＋粗糙度各三次）。低畫質檔位直接
// 不套，退回原本的單軸 UV，跟 quality.js 三檔連動。
//
// 為什麼用 onBeforeCompile 而不是自己寫 ShaderMaterial：
// MeshStandardMaterial 的光照、陰影、霧、tone mapping 一整套都要重寫，
// 而且之後 three.js 一升版就得跟著改。注入只換掉「怎麼取樣貼圖」這一段。

import * as THREE from 'three';

const VERT_HEAD = /* glsl */`
varying vec3 vTriPos;
varying vec3 vTriNrm;
`;

const VERT_BODY = /* glsl */`
  // objectNormal 由 <beginnormal_vertex> 準備好，transformed 由 <begin_vertex>
  vTriPos = (modelMatrix * vec4(transformed, 1.0)).xyz;
  vTriNrm = normalize(mat3(modelMatrix) * objectNormal);
`;

const FRAG_HEAD = /* glsl */`
varying vec3 vTriPos;
varying vec3 vTriNrm;
uniform float uTriScale;
uniform float uTriSharp;
uniform float uTriSlopeLo;
uniform float uTriSlopeHi;
#ifdef TRI_ROCK
uniform sampler2D uRockMap;
uniform sampler2D uRockNormal;
uniform sampler2D uRockRough;
#endif

// 三軸權重。法線分量取絕對值後拉高次方 —— 次方越大接縫越窄但越硬，
// 4 左右在「不糊」與「不出現三條帶」之間最平衡。
vec3 triWeights(vec3 n) {
  vec3 w = pow(abs(n), vec3(uTriSharp));
  return w / max(w.x + w.y + w.z, 1e-4);
}

vec4 triSample(sampler2D t, vec3 p, vec3 w) {
  return texture2D(t, p.zy * uTriScale) * w.x
       + texture2D(t, p.xz * uTriScale) * w.y
       + texture2D(t, p.xy * uTriScale) * w.z;
}
`;

/* 色彩：三軸取樣後，依坡度混岩石。
 * 坡度用世界法線的 y —— 1 是完全水平，0 是垂直壁面。 */
const FRAG_MAP = /* glsl */`
  vec3 triW = triWeights(vTriNrm);
  vec4 triCol = triSample(map, vTriPos, triW);
#ifdef TRI_ROCK
  float slope = 1.0 - clamp(abs(vTriNrm.y), 0.0, 1.0);
  float rockK = smoothstep(uTriSlopeLo, uTriSlopeHi, slope);
  triCol = mix(triCol, triSample(uRockMap, vTriPos, triW), rockK);
#endif
  diffuseColor *= triCol;
`;

const FRAG_ROUGH = /* glsl */`
  float roughnessFactor = roughness;
  vec4 triRough = triSample(roughnessMap, vTriPos, triW);
#ifdef TRI_ROCK
  triRough = mix(triRough, triSample(uRockRough, vTriPos, triW), rockK);
#endif
  roughnessFactor *= triRough.g;
`;

/* 法線：三軸各自的切線空間法線要先轉回世界空間才能混。
 * 用 whiteout blend（把取樣到的 xy 直接加到幾何法線的切線分量上）——
 * 比重建每個軸的 TBN 便宜得多，視覺上分不出來。 */
const FRAG_NORMAL = /* glsl */`
  vec3 triNx = triSample(normalMap, vTriPos, vec3(1.0, 0.0, 0.0)).xyz * 2.0 - 1.0;
  vec3 triNy = triSample(normalMap, vTriPos, vec3(0.0, 1.0, 0.0)).xyz * 2.0 - 1.0;
  vec3 triNz = triSample(normalMap, vTriPos, vec3(0.0, 0.0, 1.0)).xyz * 2.0 - 1.0;
#ifdef TRI_ROCK
  triNx = mix(triNx, triSample(uRockNormal, vTriPos, vec3(1.0, 0.0, 0.0)).xyz * 2.0 - 1.0, rockK);
  triNy = mix(triNy, triSample(uRockNormal, vTriPos, vec3(0.0, 1.0, 0.0)).xyz * 2.0 - 1.0, rockK);
  triNz = mix(triNz, triSample(uRockNormal, vTriPos, vec3(0.0, 0.0, 1.0)).xyz * 2.0 - 1.0, rockK);
#endif
  triNx.xy *= normalScale;
  triNy.xy *= normalScale;
  triNz.xy *= normalScale;
  vec3 triAxisN =
      vec3(0.0, triNx.y, triNx.x) * triW.x
    + vec3(triNy.x, 0.0, triNy.y) * triW.y
    + vec3(triNz.x, triNz.y, 0.0) * triW.z;
  vec3 triWorldN = normalize(vTriNrm + triAxisN);
  // 光照算在視圖空間，所以再轉一次
  normal = normalize((viewMatrix * vec4(triWorldN, 0.0)).xyz);
`;

/**
 * 把一個 MeshStandardMaterial 改成三平面取樣。
 *
 * **會就地改掉傳進來的材質**（回傳同一個物件），因為呼叫端通常已經把它
 * 掛到 mesh 上了。要保留原版請自己先 `.clone()`。
 *
 * @param {THREE.MeshStandardMaterial} mat 已經帶 map / normalMap / roughnessMap
 * @param {object} [o]
 * @param {number} [o.scale=0.08] 世界座標→貼圖座標的倍率（1/公尺）。
 *   原本的 `map.repeat` 在三平面下沒有意義，改由這個值決定紋理大小。
 * @param {number} [o.sharp=4] 三軸混合的銳利度
 * @param {object} [o.rock] 陡坡材質 `{ map, normalMap, roughnessMap }`，
 *   省略就不做坡度混合
 * @param {[number,number]} [o.slope=[0.35,0.62]] 開始/完全變成岩石的坡度
 * @returns {THREE.MeshStandardMaterial} 同一個材質
 */
export function applyTriplanar(mat, {
  scale = 0.08, sharp = 4, rock = null, slope = [0.35, 0.62],
} = {}) {
  if (!mat.map) throw new Error('applyTriplanar：材質沒有 map，三平面沒東西可採樣');

  // 三平面用世界座標，repeat 交給 uTriScale —— 留著 repeat 會被乘兩次
  for (const t of [mat.map, mat.normalMap, mat.roughnessMap]) {
    if (t) { t.repeat.set(1, 1); t.wrapS = t.wrapT = THREE.RepeatWrapping; }
  }
  if (rock) {
    for (const t of [rock.map, rock.normalMap, rock.roughnessMap]) {
      if (t) { t.repeat.set(1, 1); t.wrapS = t.wrapT = THREE.RepeatWrapping; }
    }
  }

  mat.onBeforeCompile = (sh) => {
    sh.uniforms.uTriScale = { value: scale };
    sh.uniforms.uTriSharp = { value: sharp };
    sh.uniforms.uTriSlopeLo = { value: slope[0] };
    sh.uniforms.uTriSlopeHi = { value: slope[1] };
    if (rock) {
      sh.uniforms.uRockMap = { value: rock.map };
      sh.uniforms.uRockNormal = { value: rock.normalMap || mat.normalMap };
      sh.uniforms.uRockRough = { value: rock.roughnessMap || mat.roughnessMap };
      sh.defines = { ...sh.defines, TRI_ROCK: '' };
    }

    sh.vertexShader = VERT_HEAD + sh.vertexShader.replace(
      '#include <begin_vertex>', '#include <begin_vertex>\n' + VERT_BODY);

    let f = FRAG_HEAD + sh.fragmentShader;
    f = f.replace('#include <map_fragment>', FRAG_MAP);
    if (mat.roughnessMap) f = f.replace('#include <roughnessmap_fragment>', FRAG_ROUGH);
    if (mat.normalMap) f = f.replace('#include <normal_fragment_maps>', FRAG_NORMAL);
    sh.fragmentShader = f;
  };
  // 換了 shader 就得讓 three 重新編譯，也讓它跟沒注入的材質分開快取
  mat.customProgramCacheKey = () => `tri:${scale}:${sharp}:${rock ? 1 : 0}`;
  mat.needsUpdate = true;
  return mat;
}
