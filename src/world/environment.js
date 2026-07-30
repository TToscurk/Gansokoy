// 晝夜 + 天氣的「環境系統」—— 每張地圖都能直接掛的共用模組。
//
// 一張地圖要有天色，需要的東西其實都一樣：天空球（漸層 shader）、
// 半球光、太陽（帶陰影）、補光、霧、時刻推進、天氣粒子與調色。
// 以前這一整套住在 main.js 裡，第二張圖（獸道）只能重寫一份 ——
// 現在抽成 Environment，一張圖一行 new，之後的地圖也一樣。
//
// 地圖差異用 opts 表達（霧的濃度、陰影覆蓋範圍、太陽是否跟著玩家走、
// 起始時刻…），更特殊的「地理系統」（例如地底沒有天空、雪國常年下雪）
// 之後可以再加 opts 或子類，不用改回每張圖手寫。
//
// 跨地圖連續性：時刻與天氣會在離開頁面時存進 sessionStorage，
// 走進獸道再走回神社，天色不會跳掉。

import * as THREE from 'three';
import { sample as sampleDay, clockLabel } from './daycycle.js';
import { Weather, mixHex } from './weather.js';

const HOUR_KEY = 'gansokoy:hour';
const WX_KEY = 'gansokoy:weather';

export class Environment {
  /**
   * @param {THREE.Scene} scene
   * @param {THREE.WebGLRenderer} renderer
   * @param {object} [opts]
   * @param {number}  [opts.startHour=18.3]  沒有存檔時的起始時刻
   * @param {number}  [opts.timeScale=60]    現實幾秒 = 遊戲 1 小時
   * @param {number}  [opts.fogMul=1]        霧濃度倍率（密林調高）
   * @param {number}  [opts.shadowArea=78]   陰影相機的半邊長
   * @param {THREE.Vector3} [opts.sunPivot]  太陽繞著轉的中心
   * @param {boolean} [opts.followSun=false] 太陽跟著玩家走（長條地圖用）
   * @param {number}  [opts.skyRadius=400]
   * @param {boolean} [opts.persist=true]    跨頁面記住時刻/天氣
   * @param {(t:object, wx:object)=>void} [opts.onApply]  地圖自己的追加調色
   *        （燈籠、星空、bloom…）—— 每次天色重算時回呼
   * @param {(h:number)=>void} [opts.onEnvBake] IBL 重烘時機的回呼（要用 PMREM 的圖才給）
   * @param {(text:string)=>void} [opts.onLabel] 時刻標籤更新回呼
   */
  constructor(scene, renderer, opts = {}) {
    this.scene = scene;
    this.renderer = renderer;
    this.opts = opts;

    // 預設 1 遊戲小時 = 3 分鐘（一天 72 分鐘）。之前 24 分鐘一天太快，
    // 在兩張地圖間走一趟天色就翻頁，看起來像時間不同步。
    this.timeScale = opts.timeScale ?? 180;
    this.timeFlowing = true;
    this.hour = opts.startHour ?? 18.3;
    this.persist = opts.persist !== false;
    if (this.persist) {
      try {
        const saved = parseFloat(sessionStorage.getItem(HOUR_KEY));
        if (Number.isFinite(saved)) this.hour = saved;
      } catch { /* 私隱模式 */ }
      addEventListener('beforeunload', () => this._save());
    }

    // --- 天空球：垂直漸層，時刻直接改 uniform ---
    const r = opts.skyRadius ?? 400;
    this.skyUniforms = {
      top: { value: new THREE.Color('#1d2450') },
      mid: { value: new THREE.Color('#d9663f') },
      bot: { value: new THREE.Color('#f0b070') },
    };
    this.sky = new THREE.Mesh(
      new THREE.SphereGeometry(r, 32, 20),
      new THREE.ShaderMaterial({
        side: THREE.BackSide, depthWrite: false, uniforms: this.skyUniforms,
        vertexShader: `varying vec3 vP; void main(){ vP = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.); }`,
        fragmentShader: `
          uniform vec3 top, mid, bot; varying vec3 vP;
          void main(){
            float h = clamp(vP.y/${r.toFixed(1)}*0.5+0.5, 0.0, 1.0);
            vec3 c = h < 0.5 ? mix(bot, mid, smoothstep(0.34,0.5,h))
                             : mix(mid, top, smoothstep(0.5,0.95,h));
            gl_FragColor = vec4(c,1.0);
          }`,
      })
    );
    this.sky.frustumCulled = false;
    scene.add(this.sky);

    // --- 燈光 ---
    this.hemi = new THREE.HemisphereLight('#ffd9b0', '#3a3a2a', 1.0);
    scene.add(this.hemi);

    this.sun = new THREE.DirectionalLight('#ffb066', 2.3);
    this.sun.castShadow = true;
    this.sun.shadow.mapSize.set(2048, 2048);
    const S = opts.shadowArea ?? 78;
    Object.assign(this.sun.shadow.camera, { left: -S, right: S, top: S, bottom: -S });
    this.sun.shadow.camera.near = 1;
    this.sun.shadow.camera.far = 260;
    this.sun.shadow.camera.updateProjectionMatrix();
    this.sun.shadow.bias = -0.0007;
    this.sun.shadow.normalBias = 0.04;
    // 陰影貼圖只在太陽轉了一段角度後才重畫（見 applyTime）
    this.sun.shadow.autoUpdate = false;
    this.sunPivot = (opts.sunPivot ?? new THREE.Vector3(0, 2, -2)).clone();
    this.followSun = !!opts.followSun;
    scene.add(this.sun, this.sun.target);

    this.fill = new THREE.DirectionalLight('#8fb2ff', 0.35);
    this.fill.position.set(30, 18, -40);
    scene.add(this.fill);

    // --- 霧與天氣 ---
    this.fogMul = opts.fogMul ?? 1;
    scene.fog = new THREE.FogExp2('#c9825c', 0.0075 * this.fogMul);
    this.weather = new Weather(scene);
    if (this.persist) {
      try {
        const wx = sessionStorage.getItem(WX_KEY);
        if (wx) this.weather.set(wx, 0.01);
      } catch { /* 私隱模式 */ }
    }

    this._lastEnvBakeHour = -99;
    this._lastShadowHour = -99;
    this._lastShadowPivot = new THREE.Vector3(1e9, 0, 0);
    this.ENV_BAKE_STEP = 0.2;
    this.SHADOW_STEP = 0.1;
    this.SHADOW_MOVE = 5;   // followSun 模式：玩家移動超過這距離才重畫陰影
  }

  _save() {
    try {
      sessionStorage.setItem(HOUR_KEY, this.hour.toFixed(3));
      sessionStorage.setItem(WX_KEY, this.weather.target.id);
    } catch { /* 私隱模式 */ }
  }

  get label() { return `${clockLabel(this.hour)}・${this.weather.label}`; }

  /** 把時刻 h 的天色套到場景上。forceEnvBake 讓 IBL/陰影立即重算。 */
  applyTime(h = this.hour, forceEnvBake = false) {
    const t = sampleDay(h);
    const wx = this.weather.sampleMods();

    // 天氣是「在當下時刻的基礎上偏移」：雨天的黃昏仍是黃昏色，只是更悶
    const g = wx.skyGrey, mix = wx.skyMix;
    this.skyUniforms.top.value.set(mixHex(t.sky[0], g, mix * 0.75));
    this.skyUniforms.mid.value.set(mixHex(t.sky[1], g, mix));
    this.skyUniforms.bot.value.set(mixHex(t.sky[2], g, mix * 0.9));

    this.scene.fog.color.set(mixHex(t.fog, g, mix * 0.6));
    this.scene.fog.density = t.fogD * wx.fogMul * this.fogMul;

    this.sun.color.set(t.sun);
    this.sun.intensity = t.sunI * wx.sunMul;
    const d = t.sunDir;
    this.sun.position.set(d.x, d.y, d.z).normalize().multiplyScalar(120).add(this.sunPivot);
    this.sun.target.position.copy(this.sunPivot);
    this.sun.target.updateMatrixWorld();

    // 陰影貼圖只在太陽轉了一段角度、或（followSun 模式）玩家走了一段距離
    // 之後才重畫 —— 每幀重畫會直接吃掉幀率。
    const pivotMoved = this.followSun &&
      this._lastShadowPivot.distanceToSquared(this.sunPivot) > this.SHADOW_MOVE * this.SHADOW_MOVE;
    if (forceEnvBake || pivotMoved || Math.abs(h - this._lastShadowHour) >= this.SHADOW_STEP) {
      this.sun.shadow.needsUpdate = true;
      this._lastShadowHour = h;
      this._lastShadowPivot.copy(this.sunPivot);
    }

    this.hemi.color.set(t.hemiS);
    this.hemi.groundColor.set(t.hemiG);
    this.hemi.intensity = t.hemiI;

    this.renderer.toneMappingExposure = t.exposure + wx.exposureAdd;
    this.scene.environmentIntensity = t.env * wx.envMul;

    this.opts.onApply?.(t, wx);

    if (this.opts.onEnvBake &&
        (forceEnvBake || Math.abs(h - this._lastEnvBakeHour) >= this.ENV_BAKE_STEP)) {
      this.opts.onEnvBake(h);
      this._lastEnvBakeHour = h;
    }

    this.opts.onLabel?.(this.label);
  }

  /**
   * 每幀呼叫：推進時刻、更新天氣粒子、需要時重套天色。
   * @param {THREE.Vector3} camPos 相機/玩家位置（天空球與天氣粒子跟著走）
   */
  update(dt, camPos) {
    if (this.timeFlowing) this.hour = (this.hour + dt / this.timeScale) % 24;
    this.weather.update(dt, camPos);
    if (this.followSun && camPos) this.sunPivot.set(camPos.x, 2, camPos.z);
    if (this.timeFlowing || this.weather.blend < 1 || this.followSun) this.applyTime(this.hour);
    this.sky.position.copy(camPos ?? this.sky.position);

    // 每幾秒存一次時刻/天氣 —— 只靠 beforeunload 的話，瀏覽器閃退或
    // 行動裝置直接殺分頁就會掉狀態，跨地圖的天色就對不上了。
    if (this.persist) {
      this._saveAcc = (this._saveAcc ?? 0) + dt;
      if (this._saveAcc > 4) { this._saveAcc = 0; this._save(); }
    }
  }

  /** 測試/熱鍵用：直接設時刻並停住時間 */
  setHour(h, freeze = true) {
    this.hour = ((h % 24) + 24) % 24;
    if (freeze) this.timeFlowing = false;
    this.applyTime(this.hour, true);
    return clockLabel(this.hour);
  }

  setWeather(id, dur = 3) {
    this.weather.set(id, dur);
    this._save();
  }
}
