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
//   ctrl.update → kit.update → onUpdate → env.update → onLateUpdate
//   → minimap.update → render
// onUpdate / onLateUpdate 拆成兩個掛勾不是過度設計 —— 花田的向日葵
// 追日要讀 env.update 之後的太陽方位，怪物 AI 卻要在 kit 結算之後、
// env 之前跑，一個掛勾包不住原本的順序。

import * as THREE from 'three';
import { buildCharacter } from '../entities/model.js';
import { ACTIVE_PLAYABLE, DEFAULT_PLAYER } from '../entities/roster.js';
import { PlayerController } from '../player/controller.js';
import { Environment } from '../world/environment.js';
import { Progression } from '../player/progression.js';
import { installLoadout } from '../player/loadout.js';
import { installHUD, bindEscMenu } from '../ui/hud.js';
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
export function bootMap({ hud, camera: camOpts = {}, exposure = 1.06, env: envOpts }) {
  const HUD = installHUD(hud);

  const renderer = new THREE.WebGLRenderer({ antialias: true });
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

  let qualityIdx = loadQualityIdx(2);
  const syncQuality = () => {
    applyBasicQuality(renderer, env.sun, qualityIdx);
    HUD.qualLabel.textContent = `畫質：${QUALITY_NAMES[qualityIdx]}`;
  };
  syncQuality();

  const world = new THREE.Group();
  scene.add(world);
  const colliders = [];

  const core = {
    THREE, HUD, renderer, scene, camera, env, world, colliders,
    // 之後各階段逐一填上
    spec: null, model: null, ctrl: null, prog: null, kit: null,
    escMenu: null, worldMap: null, minimap: null,
    _updates: [], _lateUpdates: [],
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
      let saved = null;
      try { saved = sessionStorage.getItem('gansokoy:char'); } catch { /* 私隱模式 */ }
      const spec = ACTIVE_PLAYABLE.find(p => p.id === saved) ?? DEFAULT_PLAYER;

      const model = buildCharacter(spec);
      scene.add(model);
      const ctrl = new PlayerController(model, camera, renderer.domElement, colliders);
      ctrl.canFly = spec.canFly ?? true;
      ctrl.maxAirJumps = spec.airJumps ?? 0;
      ctrl.jumpV = spec.jump ?? 9.2;
      ctrl.airJumpV = spec.airJump ?? 8.4;
      ctrl.sprintMul = spec.sprintMul ?? 1.85;
      ctrl.speedMul = spec.speed ?? 1.0;
      if (bounds) ctrl.bounds = bounds;
      if (maxGrade != null) ctrl.maxGrade = maxGrade;

      spawn(new URLSearchParams(location.search).get('from'), ctrl);

      core.spec = spec;
      core.model = model;
      core.ctrl = ctrl;
      return { spec, model, ctrl };
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

    /* ───────────────────────────────────────── ESC 選單 ── */
    bindEsc({ isBusy, onBackToSelect } = {}) {
      core.escMenu = bindEscMenu({
        getCtrl: () => core.ctrl,
        env,
        quality: {
          get: () => QUALITY_NAMES[qualityIdx],
          cycle() {
            qualityIdx = (qualityIdx + 1) % QUALITY_NAMES.length;
            saveQualityIdx(qualityIdx);
            syncQuality();
            return QUALITY_NAMES[qualityIdx];
          },
        },
        isBusy,
        onBackToSelect: onBackToSelect ?? (() => {
          HUD.showLoading('博麗神社 讀取中');
          location.href = '../../index.html';
        }),
      });
      return core.escMenu;
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

    /** 一格模擬（debug handle 的 step 也走這裡 —— 測試與遊戲同一條路徑） */
    tick(rawDt) {
      let dt = rawDt;
      if (core.kit?.combat?.hitstop > 0) dt *= 0.12;
      core._t += dt;
      const t = core._t;
      core.ctrl?.update(dt, t);
      core.kit?.update(dt, rawDt);
      for (const fn of core._updates) fn(dt, rawDt, t);
      env.update(dt, camera.position);
      for (const fn of core._lateUpdates) fn(dt, rawDt, t);
      core.minimap?.update();
    },

    start() {
      addEventListener('resize', () => {
        camera.aspect = innerWidth / innerHeight;
        camera.updateProjectionMatrix();
        renderer.setSize(innerWidth, innerHeight);
      });
      const loading = document.getElementById('loading');
      if (loading) loading.style.display = 'none';
      const animate = () => {
        core.tick(Math.min(core._clock.getDelta(), 0.05));
        renderer.render(scene, camera);
        requestAnimationFrame(animate);
      };
      animate();
    },

    /* ─────────────────────────── debug handle（測試口徑統一） ── */
    debugHandle(extra = {}) {
      return {
        renderer, scene, camera, THREE, env, colliders,
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
        frame() { renderer.render(scene, camera); },
        setHour(h) { return env.setHour(h); },
        setTimeFlowing(v) { env.timeFlowing = v; },
        ...extra,
      };
    },
  };

  return core;
}
