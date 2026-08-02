// GameCore —— 統一執行層（共用系統整合書・階段 A）。
//
// 診斷（整合書 §1）：模組其實切得夠細，問題在「組裝」—— 每張圖都要
// 自己把 renderer / camera / Environment / HUD / 玩家 / 成長 / ESC 選單 /
// 大小地圖 / resize / animate 這一整套重新接一次線，六張圖一字不差的
// 樣板就有一百多行。後果是功能孤島：先做的圖有的東西，後做的圖沒有。
//
// 這個檔案是**唯一的組裝點**。地圖檔案只寫「這張圖獨有的東西」：
//
//   const core = bootMap({ hud: {...}, camera: {...}, env: {...} });
//   // …地形、建築、怪、NPC（用 core.world / core.colliders）…
//   core.spawnPlayer({ bounds, maxGrade, spawn(from, ctrl) {...} });
//   const prog = core.createProgression();
//   const kit = core.installKit({ mobs, isBlocked, onDeath });
//   core.bindEsc();
//   core.installMapUI({ current: 'xxx', minimap: {...}, isBlocked });
//   core.onUpdate((dt, rawDt, t) => { /* 怪/NPC/對話 */ });
//   core.onLateUpdate((dt, rawDt, t) => { /* 需要在 env 之後的：追日、提示 */ });
//   core.start();
//   window.__xxx = core.debugHandle({ /* 圖專屬的常數 */ });
//
// 遷移守則（整合書 §5）：這是重構不是加功能 —— 每張圖遷移後的
// 成功標準是「行為完全不變」。更新順序刻意保留原樣板的每一步：
//   onPreTick → [tickWhen 閘門：ctrl.update → kit.update → onUpdate
//   → env.update → onLateUpdate] → onPreMinimap → minimap.update
//   → onPostUpdate → render
// onUpdate / onLateUpdate 拆成兩個掛勾不是過度設計 —— 花田的向日葵
// 追日要讀 env.update 之後的太陽方位，怪物 AI 卻要在 kit 結算之後、
// env 之前跑，一個掛勾包不住原本的順序。

import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { GTAOPass } from 'three/addons/postprocessing/GTAOPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { SMAAPass } from 'three/addons/postprocessing/SMAAPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { buildCharacter } from '../entities/model.js';
import { ACTIVE_PLAYABLE, DEFAULT_PLAYER } from '../entities/roster.js';
import { PlayerController } from '../player/controller.js';
import { Environment } from '../world/environment.js';
import { setGroundHeightFn } from '../world/terrain.js';
import { WORLD } from '../config.js';
import { HazardZones } from '../world/hazard.js';
import { Progression } from '../player/progression.js';
import { installLoadout } from '../player/loadout.js';
import { installHUD, bindEscMenu } from '../ui/hud.js';
import { TALK_RANGE } from '../entities/npc.js';
import { installWorldMap } from '../ui/worldmap.js';
import { installMinimap } from '../ui/minimap.js';
import { loadQualityIdx, saveQualityIdx, applyBasicQuality, QUALITY_NAMES } from '../world/quality.js';

/**
 * 開機：HUD、renderer、scene/camera、Environment、畫質、world 群組與
 * colliders 陣列。這一步之後地圖就可以開始蓋世界。
 *
 * @param {object} o
 * @param {object} o.hud  installHUD 的參數（title/subtitle/keys/flyKeys/combatKeys）
 * @param {object} [o.camera]  { fov=68, far=700 }
 * @param {number} [o.exposure=1.06]  toneMappingExposure
 * @param {object} o.env  Environment 的參數（fogMul/shadowArea/followSun…）
 */
export function bootMap({
  hud, camera: camOpts = {}, exposure = 1.06, env: envOpts, postFX = 'basic',
  renderer: rendererOpts = {}, clock = false, tickWhen = null,
}) {
  const HUD = installHUD(hud);

  // 神社是 antialias:false + powerPreference:'high-performance'（走 composer 時
  // MSAA 對主畫面無效，只有直接畫上 canvas 的名牌吃得到）—— 可覆寫。
  const renderer = new THREE.WebGLRenderer({ antialias: true, ...rendererOpts });
  renderer.setSize(innerWidth, innerHeight);
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = exposure;
  document.body.appendChild(renderer.domElement);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(
    camOpts.fov ?? 68, innerWidth / innerHeight, camOpts.near ?? 0.2, camOpts.far ?? 700,
  );
  camera.rotation.order = 'YXZ';

  const env = new Environment(scene, renderer, envOpts);

  /* ─────────────────────── 後製鏈（postFX: 'full'，整合書階段 B） ──
   * 神社的那一套：Render → GTAO → Bloom → OutputPass（色調映射）→
   * 分級（對比/飽和/暗部冷偏/暈影）→ SMAA。參數照抄 main.js ——
   * 這是「消除畫質雙標」，不是調一套新的看起來的樣子。
   * 檔位對映也照神社：低＝全關（只剩 Render+Output）、中＝Bloom+分級
   * +SMAA、高＝再加 GTAO。'basic' 圖維持 applyBasicQuality（無 composer）。 */
  let composer = null, fx = null;
  if (postFX === 'full') {
    composer = new EffectComposer(renderer);
    composer.addPass(new RenderPass(scene, camera));
    const gtao = new GTAOPass(scene, camera, innerWidth, innerHeight);
    gtao.output = GTAOPass.OUTPUT.Default;
    gtao.updateGtaoMaterial({
      radius: 1.6, distanceExponent: 1.2, thickness: 1.5, scale: 1.2,
      samples: 16, distanceFallOff: 1, screenSpaceRadius: false,
    });
    gtao.updatePdMaterial({ lumaPhi: 10, depthPhi: 2, normalPhi: 3, radius: 4, rings: 2, samples: 16 });
    composer.addPass(gtao);
    const bloom = new UnrealBloomPass(new THREE.Vector2(innerWidth, innerHeight), 0.34, 0.45, 1.15);
    composer.addPass(bloom);
    composer.addPass(new OutputPass());
    const gradePass = new ShaderPass({
      uniforms: {
        tDiffuse: { value: null },
        contrast: { value: 1.11 },
        saturation: { value: 1.12 },
        vignette: { value: 0.45 },
        tint: { value: new THREE.Color('#2a1c3a') },
        // 色調分級 LUT（升級書 4.4）。預設沒有貼圖、強度 0 ——
        // 地圖要用就呼叫 core.setLUT()，不用的圖一個指令都不多跑。
        tLut: { value: null },
        lutSize: { value: 16 },
        lutMix: { value: 0 },
      },
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.); }',
      fragmentShader: `
        uniform sampler2D tDiffuse; uniform float contrast, saturation, vignette;
        uniform vec3 tint; varying vec2 vUv;
        uniform sampler2D tLut; uniform float lutSize, lutMix;

        // 條狀 LUT：N 個藍色切片橫向排開，寬 N*N、高 N。
        // 半個像素的內縮是必要的 —— 沒有的話紅色軸取樣會滲到隔壁切片，
        // 畫面上會出現一格一格的色塊。
        vec3 lutLookup(vec3 c){
          float N = lutSize;
          c = clamp(c, 0.0, 1.0);
          float b = c.b * (N - 1.0);
          float b0 = floor(b), b1 = min(b0 + 1.0, N - 1.0);
          float fb = b - b0;
          float u = (0.5 + c.r * (N - 1.0)) / N;
          float v = (0.5 + c.g * (N - 1.0)) / N;
          vec3 s0 = texture2D(tLut, vec2((b0 + u) / N, v)).rgb;
          vec3 s1 = texture2D(tLut, vec2((b1 + u) / N, v)).rgb;
          return mix(s0, s1, fb);
        }

        void main(){
          vec4 src = texture2D(tDiffuse, vUv);
          vec3 c = src.rgb;
          c = (c - 0.5) * contrast + 0.5;
          float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
          c = mix(vec3(l), c, saturation);
          c = mix(c, tint, (1.0 - l) * 0.09);
          if (lutMix > 0.0) c = mix(c, lutLookup(clamp(c, 0.0, 1.0)), lutMix);
          float v = smoothstep(0.95, 0.28, length(vUv - 0.5));
          c *= mix(1.0, v, vignette);
          gl_FragColor = vec4(clamp(c, 0.0, 1.0), src.a);
        }`,
    });
    composer.addPass(gradePass);
    const smaa = new SMAAPass();
    composer.addPass(smaa);
    fx = { gtao, bloom, gradePass, smaa };
  }
  const FULL_QUALITY = [
    { dpr: 1.0, shadow: 1024, gtao: false, bloom: false, smaa: false, grade: false },
    { dpr: 1.25, shadow: 2048, gtao: false, bloom: true, smaa: true, grade: true },
    { dpr: 1.5, shadow: 4096, gtao: true, bloom: true, smaa: true, grade: true },
  ];

  let qualityIdx = loadQualityIdx(2);
  const syncQuality = () => {
    if (fx) {
      const q = FULL_QUALITY[qualityIdx] ?? FULL_QUALITY[2];
      renderer.setPixelRatio(Math.min(devicePixelRatio, q.dpr));
      renderer.setSize(innerWidth, innerHeight);
      composer.setSize(innerWidth, innerHeight);
      fx.gtao.enabled = q.gtao;
      fx.bloom.enabled = q.bloom;
      fx.smaa.enabled = q.smaa;
      fx.gradePass.enabled = q.grade;
      const sun = env.sun;
      if (sun && sun.shadow.mapSize.x !== q.shadow) {
        sun.shadow.mapSize.set(q.shadow, q.shadow);
        sun.shadow.map?.dispose();
        sun.shadow.map = null;
        sun.shadow.needsUpdate = true;
      }
    } else {
      applyBasicQuality(renderer, env.sun, qualityIdx);
    }
    HUD.qualLabel.textContent = `畫質：${QUALITY_NAMES[qualityIdx]}`;
    for (const fn of _qualityListeners) fn(qualityIdx, QUALITY_NAMES[qualityIdx]);
  };
  const _qualityListeners = [];
  syncQuality();

  const world = new THREE.Group();
  scene.add(world);
  const colliders = [];

  // 名牌 overlay：depthTest:false 的 sprite 不能進後製鏈（GTAO 會把它
  // 塗成黑方塊，README 踩坑 #3）。名牌一律住這個場景，主畫面畫完再疊。
  const labelScene = new THREE.Scene();

  // Environment 的三個回呼插槽（onApply / onEnvBake / onLabel）本來都是
  // 「後面指派的把前面蓋掉」的單一插槽。後製鏈要接 onApply（bloom 強度與
  // 飽和跟時刻走），圖自己也常要接（燈籠、紙窗、星空）—— 兩邊直接指派
  // 就會互相吃掉，而且**當下完全看不出錯**：basic 圖的清單本來就是空的，
  // 等到哪天升成 postFX:'full' 才會發現後製那份被靜默吃了。
  // 三個一律改成清單制，地圖端用 core.onEnvApply / onEnvBake / onEnvLabel。
  const _envApply = [], _envBake = [], _envLabel = [];
  env.opts.onApply = (t, wx) => { for (const fn of _envApply) fn(t, wx); };
  env.opts.onEnvBake = (h) => { for (const fn of _envBake) fn(h); };
  env.opts.onLabel = (text) => { for (const fn of _envLabel) fn(text); };
  if (fx) {
    _envApply.push((t, wx) => {
      fx.bloom.strength = t.bloom;
      fx.gradePass.uniforms.saturation.value = t.sat * wx.satMul;
    });
  }
  // 右上角時刻顯示：整合書階段 C 表列的孤島之一（原本只有神社與人里有）。
  // HUD 本來就有 #todLabel 這個空位，接上去就是全圖標配 —— 但**開啟它是加
  // 功能，不是重構**，所以預設關閉。遷移期一律不傳；等七張圖都遷完，
  // 再用一個獨立 commit 把預設改成 true（那時才是階段 C 的孤島修補）。
  if (clock) _envLabel.push((text) => { if (HUD.todLabel) HUD.todLabel.textContent = text; });

  const core = {
    THREE, HUD, renderer, scene, camera, env, world, colliders,
    composer, fx, labelScene,
    onEnvApply(fn) { _envApply.push(fn); },
    onEnvBake(fn) { _envBake.push(fn); },
    onEnvLabel(fn) { _envLabel.push(fn); },

    /** 名牌該住哪個場景：有後製鏈才需要 overlay（GTAO 會把 depthTest:false
     *  的 sprite 塗黑）。圖一律寫 new NPCManager(scene, core.plateScene)，
     *  之後切 postFX 不必回頭改地圖。 */
    get plateScene() { return composer ? labelScene : scene; },

    /**
     * 登記地形高度場（G3）。**刻意做成方法而不是 bootMap 參數** ——
     * kourindou / trail 的 heightAt 反向依賴 PathNet，登記時機得由地圖決定。
     */
    setTerrain(heightAt, { waterLevel = -999 } = {}) {
      core.heightAt = heightAt;
      setGroundHeightFn(heightAt);
      WORLD.waterLevel = waterLevel;
      return heightAt;
    },

    /**
     * 立刻套一次天色（G8）。Environment 的建構子不呼叫 applyTime，而
     * onEnvBake 只在 force 或太陽轉夠角度時才觸發 —— 需要 IBL 或
     * 「第 0 幀燈籠就該是對的」的圖必須顯式呼叫，且要排在所有
     * onEnvApply / onEnvBake / onEnvLabel 註冊**之後**。
     */
    applyEnvNow(force = true) { env.applyTime(env.hour, force); },
    // 之後各階段逐一填上
    spec: null, model: null, ctrl: null, prog: null, kit: null,
    escMenu: null, worldMap: null, minimap: null,
    hazards: null,
    _updates: [], _lateUpdates: [], _postUpdates: [], _preTicks: [], _preMinimap: [],
    heightAt: null,
    _t: 0,
    _clock: new THREE.Clock(),

    /* ───────────────────────────────── 建造小工具（各圖同一套） ── */
    block(x, z, sx, sz, top, bottom = -99) {
      colliders.push({ x, z, y: bottom, h: top - bottom, hw: sx / 2, hd: sz / 2 });
    },
    walkBlock(x, z, sx, sz, top, bottom = -99) {
      colliders.push({ x, z, y: bottom, h: top - bottom, hw: sx / 2, hd: sz / 2, walk: true });
    },
    post(x, z, r, top, bottom = -99) {
      colliders.push({ x, z, y: bottom, h: top - bottom, r });
    },
    box(sx, sy, sz, mat, x, y, z, parent = world) {
      const m = new THREE.Mesh(new THREE.BoxGeometry(sx, sy, sz), mat);
      m.position.set(x, y, z);
      m.castShadow = m.receiveShadow = true;
      parent.add(m);
      return m;
    },
    cyl(r1, r2, h, mat, x, y, z, seg = 8, parent = world) {
      const m = new THREE.Mesh(new THREE.CylinderGeometry(r1, r2, h, seg), mat);
      m.position.set(x, y, z);
      m.castShadow = m.receiveShadow = true;
      parent.add(m);
      return m;
    },

    /* ───────────────────────────────────────────────── 玩家 ── */
    /**
     * @param {object} o { bounds:{hx,hz}, maxGrade, spawn(from, ctrl) }
     *   spawn 拿到 ?from= 的值與 ctrl，自行 teleport 與轉向。
     */
    spawnPlayer({ bounds, maxGrade, spawn }) {
      const r = core.createPlayer({ bounds, maxGrade });
      spawn(new URLSearchParams(location.search).get('from'), r.ctrl);
      return r;
    },

    /* ─────────────────────────────────── 成長 + 隨身裝備 ── */
    createProgression() {
      core.prog = new Progression({
        onLevelUp: (msg) => { HUD.toast(msg); core.kit?.skills?.onLevelUp(); },
      });
      return core.prog;
    },

    /** installLoadout 的樣板。mobs 可不傳（safe 圖）。 */
    installKit({ mobs, isBlocked, onDeath }) {
      core.kit = installLoadout({
        getSpec: () => core.spec, getCtrl: () => core.ctrl,
        scene, HUD, prog: core.prog, mobs,
        isBlocked, onDeath,
      });
      core.prog.renderBadge(core.spec.combat ? 'hinokami' : null, '日之呼吸');
      return core.kit;
    },

    /* ─────────────────────────── 畫質控制面（G15） ── */
    /** 神社的 G 鍵、FPS 自動降檔、ESC 選單三個地方都要能「指定索引」並帶
     *  自己的副作用（autoTuned 旗標、toast 檔位名）。原本 qualityIdx 是
     *  bootMap 的閉包私有，只有 escMenu 的 cycle 摸得到。 */
    quality: {
      get idx() { return qualityIdx; },
      get name() { return QUALITY_NAMES[qualityIdx]; },
      names: QUALITY_NAMES,
      /** 三檔的實際映射（dpr / 陰影貼圖 / 各 pass 開關）。神社的 debug
       *  handle 原本就把整張表掛在 __shrine.QUALITY 上，遷移後不該只剩
       *  name —— 唯讀，地圖端請自己 spread 一份出去。 */
      tiers: FULL_QUALITY,
      set(i) {
        qualityIdx = Math.max(0, Math.min(QUALITY_NAMES.length - 1, i));
        saveQualityIdx(qualityIdx);
        syncQuality();
        return QUALITY_NAMES[qualityIdx];
      },
      cycle() { return core.quality.set((qualityIdx + 1) % QUALITY_NAMES.length); },
    },
    onQualityChange(fn) { _qualityListeners.push(fn); },

    /**
     * 掛上這張圖的色調分級 LUT（升級書 4.4）。
     *
     * 只有 postFX:'full' 才有 gradePass —— basic 那條路沒有後製鏈，
     * 呼叫會被安靜忽略（回傳 false），地圖端不必自己判斷。
     * 低畫質檔位 gradePass 本來就關掉，所以 LUT 也跟著失效，不必另外連動。
     *
     * @param {THREE.DataTexture|null} tex buildLUT() 的產物；null ＝取消
     * @param {number} [mix=1] 0~1，想要淡一點就調低
     * @returns {boolean} 有沒有真的掛上
     */
    setLUT(tex, mix = 1) {
      if (!fx || !fx.gradePass) return false;
      const u = fx.gradePass.uniforms;
      u.tLut.value = tex;
      u.lutSize.value = tex?.userData?.lutSize ?? 16;
      u.lutMix.value = tex ? mix : 0;
      return !!tex;
    },

    /* ─────────────────────── 玩家生命週期（G14） ── */
    /**
     * 建立（或重建）玩家。神社是唯一一張「選角之前沒有玩家、之後還能中途
     * 換角」的圖 —— 重複呼叫時先 dispose 舊的 controller 並把舊 model 移出
     * 場景，不然舊的 DOM 監聽器會繼續吃輸入。
     * @param {object} o { spec, bounds, maxGrade, keepPos }
     *   spec 省略＝照 sessionStorage 挑；keepPos＝沿用舊玩家的座標與朝向。
     */
    createPlayer({ spec = null, bounds = null, maxGrade = null, keepPos = false } = {}) {
      const prev = core.ctrl;
      const prevPos = prev ? prev.pos.clone() : null;
      const prevYaw = prev ? prev.yaw : 0;
      const prevCamYaw = prev ? prev.camYaw : Math.PI;
      if (prev) {
        prev.dispose?.();
        if (core.model) scene.remove(core.model);
      }

      let use = spec;
      if (!use) {
        let saved = null;
        try { saved = sessionStorage.getItem('gansokoy:char'); } catch { /* 私隱模式 */ }
        use = ACTIVE_PLAYABLE.find(p => p.id === saved) ?? DEFAULT_PLAYER;
      }

      const model = buildCharacter(use);
      scene.add(model);
      const ctrl = new PlayerController(model, camera, renderer.domElement, colliders);
      ctrl.canFly = use.canFly ?? true;
      ctrl.maxAirJumps = use.airJumps ?? 0;
      ctrl.jumpV = use.jump ?? 9.2;
      ctrl.airJumpV = use.airJump ?? 8.4;
      ctrl.sprintMul = use.sprintMul ?? 1.85;
      ctrl.speedMul = use.speed ?? 1.0;
      if (bounds) ctrl.bounds = bounds;
      if (maxGrade != null) ctrl.maxGrade = maxGrade;
      if (keepPos && prevPos) {
        ctrl.teleport(prevPos.x, prevPos.z);
        ctrl.yaw = prevYaw;
        ctrl.camYaw = prevCamYaw;
      }

      core.spec = use;
      core.model = model;
      core.ctrl = ctrl;
      return { spec: use, model, ctrl };
    },

    /** 記住選了誰（換角/重整之後回到同一位） */
    setSavedChar(id) {
      try { sessionStorage.setItem('gansokoy:char', id); } catch { /* 私隱模式 */ }
    },

    /* ───────────────────────────────────────── ESC 選單 ── */
    bindEsc({ isBusy, onBackToSelect, quality } = {}) {
      core.escMenu = bindEscMenu({
        getCtrl: () => core.ctrl,
        env,
        quality: quality ?? {
          get: () => core.quality.name,
          cycle: () => core.quality.cycle(),
        },
        isBusy,
        onBackToSelect: onBackToSelect ?? (() => {
          HUD.showLoading('博麗神社 讀取中');
          location.href = '../../index.html';
        }),
      });
      return core.escMenu;
    },

    /**
     * 環境傷害區（G11）。**排序就是行為**：hazards.update 必須排在
     * kit.update 之後（vitals 要先結算完無敵幀）、env.update 之前，
     * 而且要早於地圖自己的 onUpdate —— 順序顛倒就變成「先跳提示才扣血」。
     * 由這裡代註冊，之後 forest 上線不必再抄一次順序。
     */
    installHazards(build) {
      const hz = new HazardZones(core.kit.vitals);
      build?.(hz);
      core.onUpdate((dt) => hz.update(dt, core.ctrl.pos));
      core.hazards = hz;
      return hz;
    },

    /* ──────────────────────── E 鍵互動 + 出口提示（樣板收攏） ── */
    /**
     * 每張圖都有的那三十行：E 鍵先讓 ESC 選單、對話中只推進、沒鎖定不理，
     * 再依序試「附近有 NPC 就對話」→「站在某個出口就換圖」；
     * 而 HUD 提示是同一組判定的鏡像。兩段判定順序必須一致 —— 分開寫
     * 遲早會漂移（提示說能按 E，按下去卻沒反應），所以由這裡一起產出。
     *
     * **回傳 updatePrompt()，由地圖自己決定在 onLateUpdate 的哪一格呼叫** ——
     * 沒有自動註冊。原因：提示區塊在各圖原本的相對位置不同（多半在
     * 傳送點呼吸動畫之後），自動註冊就等於偷偷改順序，而順序就是行為。
     *
     * @param {object} o
     * @param {object} [o.npcMgr]   有 NPC 的圖才傳
     * @param {object} [o.dialogue]
     * @param {{near:()=>boolean, prompt:string, href?:string, loading?:string}[]} o.exits
     *        href 省略 = 只顯示提示、按 E 不傳送（例：還沒蓋的魔法之森）
     * @param {(...)=>boolean} [o.onInteract] 額外的 E 互動（賽錢箱之類）。
     *        回傳 true 表示已處理，後面的出口判定就不跑。
     */
    installTalk({ npcMgr = null, dialogue = null, exits = [], onInteract = null } = {}) {
      const nearNpc = () => {
        if (!npcMgr) return null;
        const npc = npcMgr.nearest;
        return (npc && npc.pos.distanceTo(core.ctrl.pos) <= TALK_RANGE) ? npc : null;
      };

      window.addEventListener('keydown', (e) => {
        if (e.code !== 'KeyE' || core.escMenu?.isOpen) return;
        if (dialogue?.active) { dialogue.advance(); return; }
        if (!core.ctrl?.locked) return;

        const npc = nearNpc();
        if (npc) {
          core.ctrl.enabled = false;
          dialogue.open(npc.spec, npcMgr.nextTalk(npc), () => { core.ctrl.enabled = true; });
          return;
        }
        if (onInteract?.()) return;
        for (const ex of exits) {
          if (!ex.near()) continue;
          if (!ex.href) return;                 // 有提示、沒有路（未開放的出口）
          HUD.showLoading(ex.loading ?? '讀取中');
          location.href = ex.href;
          return;
        }
      });

      return function updatePrompt() {
        if (dialogue?.active) { HUD.prompt(null); return; }
        const npc = nearNpc();
        if (npc) { HUD.prompt(`[ E ]  與 ${npc.spec.zh} 對話`); return; }
        for (const ex of exits) {
          if (ex.near()) { HUD.prompt(ex.prompt); return; }
        }
        HUD.prompt(null);
      };
    },

    /* ─────────────────────────── 大地圖 + 小地圖（升級5） ── */
    installMapUI({ current, isBlocked, minimap }) {
      core.worldMap = installWorldMap({ current, isBlocked });
      if (minimap) {
        core.minimap = installMinimap({
          ...minimap,
          getPos: () => core.ctrl?.pos,
          getYaw: () => core.ctrl?.yaw ?? 0,
        });
      }
      return { worldMap: core.worldMap, minimap: core.minimap };
    },

    /* ─────────────────────────────────────────── 主迴圈 ── */
    onUpdate(fn) { core._updates.push(fn); },
    onLateUpdate(fn) { core._lateUpdates.push(fn); },
    /** 每個 rAF、core.tick 的子系統跑之前（G12）。神社的 canvas 0×0 重同步
     *  與 FPS 自動降檔住這裡 —— 它們在原本的 animate 裡就排在 update() 之前，
     *  塞進 onUpdate 會變成 ctrl.update 之後，晚了一格。
     *  簽名 (dt, rawDt, t)：dt 已套過 hitstop、t 已推進，與原本逐字相同。 */
    onPreTick(fn) { core._preTicks.push(fn); },
    /** 閘門**之外**、minimap.update() 之前的掛勾。神社的傳送點呼吸動畫住這裡：
     *  它原本在 animate 裡、在 update()（＝tickWhen 的閘門）外面，而且排在
     *  minimap 之前 —— onLateUpdate 會被閘門擋掉，onPostUpdate 又跑在 minimap
     *  之後，兩個都不對，所以補這一格。 */
    onPreMinimap(fn) { core._preMinimap.push(fn); },
    /** minimap.update() **之後**的掛勾（G1）。神社的陰陽玉/鈴緒/光塵三段
     *  動畫原本就排在小地圖之後 —— 實務影響大概是零（minimap 只讀
     *  ctrl.pos/yaw），但「相對位置」就是行為，給地圖一個逐字保序的選項。 */
    onPostUpdate(fn) { core._postUpdates.push(fn); },

    /** 一格模擬（debug handle 的 step 也走這裡 —— 測試與遊戲同一條路徑） */
    tick(rawDt) {
      let dt = rawDt;
      if (core.kit?.combat?.hitstop > 0) dt *= 0.12;
      core._t += dt;
      const t = core._t;
      for (const fn of core._preTicks) fn(dt, rawDt, t);
      // tickWhen（G13）：神社在選角之前 ctrl 是 null，原本的 update() 第一行
      // 就 return —— 連 env.update 都不跑，所以標題畫面上時刻是**凍結**的
      // （而 Environment 會把時刻寫進 localStorage，不凍結就會偷偷流掉）。
      // 閘門的範圍刻意跟原本的 update() 一致：ctrl / kit / onUpdate / env /
      // onLateUpdate 被擋，minimap 與 onPostUpdate 照跑（原本它們在 animate
      // 裡、在 update() 外面）。
      if (!tickWhen || tickWhen()) {
        core.ctrl?.update(dt, t);
        core.kit?.update(dt, rawDt);
        for (const fn of core._updates) fn(dt, rawDt, t);
        env.update(dt, camera.position);
        for (const fn of core._lateUpdates) fn(dt, rawDt, t);
      }
      for (const fn of core._preMinimap) fn(dt, rawDt, t);
      core.minimap?.update();
      for (const fn of core._postUpdates) fn(dt, rawDt, t);
    },

    /** 一幀：後製鏈（有的話）＋名牌 overlay。 */
    renderFrame() {
      if (composer) composer.render();
      else renderer.render(scene, camera);
      if (labelScene.children.length) {
        const prev = renderer.autoClear;
        renderer.autoClear = false;          // 別把剛畫好的畫面清掉
        renderer.setRenderTarget(null);
        renderer.render(labelScene, camera);
        renderer.autoClear = prev;
      }
    },

    start() {
      addEventListener('resize', () => {
        camera.aspect = innerWidth / innerHeight;
        camera.updateProjectionMatrix();
        renderer.setSize(innerWidth, innerHeight);
        composer?.setSize(innerWidth, innerHeight);
      });
      const loading = document.getElementById('loading');
      if (loading) loading.style.display = 'none';
      const animate = () => {
        core.tick(Math.min(core._clock.getDelta(), 0.05));
        core.renderFrame();
        requestAnimationFrame(animate);
      };
      animate();
    },

    /* ─────────────────────────── debug handle（測試口徑統一） ── */
    /**
     * @param {object} extra 圖專屬欄位。**展開在最後，所以可以覆寫
     *   tp / step / frame** —— 神社的三個都跟 GameCore 版語意不同，
     *   遷移時記得覆寫回去。
     * @param {{omit?:string[]}} [o] omit：拿掉指定的鍵（例：原本沒有 composer）
     */
    debugHandle(extra = {}, { omit = [] } = {}) {
      const h = {
        renderer, scene, camera, THREE, env, colliders,
        ...(core.heightAt ? { heightAt: core.heightAt } : {}),
        get ctrl() { return core.ctrl; },
        get prog() { return core.prog; },
        get vitals() { return core.kit?.vitals; },
        get skills() { return core.kit?.skills; },
        get combat() { return core.kit?.combat; },
        get panel() { return core.kit?.panel; },
        get kit() { return core.kit; },
        tp(x, z, yaw = 0) { core.ctrl.teleport(x, z); core.ctrl.yaw = yaw; },
        step(n = 1, dt = 0.016) {
          for (let i = 0; i < n; i++) core.tick(dt);
          return core.ctrl.pos.toArray().map(v => +v.toFixed(2));
        },
        frame() { core.renderFrame(); },
        // basic 圖原本沒有 composer 這個 key —— 值是 null 就不要放進去，
        // 免得 Object.keys / `in` 的快照比對出現假差異。
        ...(composer ? { composer } : {}),
        setHour(hh) { return env.setHour(hh); },
        setTimeFlowing(v) { env.timeFlowing = v; },
        ...extra,
      };
      for (const k of omit) delete h[k];
      return h;
    },
  };

  return core;
}
