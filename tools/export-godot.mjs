// Godot 遷移・烘焙工具 —— 把現有 three.js 地圖烤成 .glb 底稿（blockout）。
//
// 混合路線（佈局搬、視覺在 Godot 重做）的第一步：
//   1. 起 dev-server，用無頭 Chromium 逐張開啟已建成的地圖
//   2. 透過 GameCore 掛的 window.__godotExport 抓 world 群組（純靜態幾何，
//      NPC / 怪 / 玩家都掛在 scene 上，不會混進來）
//   3. 用 three 的 GLTFExporter 烤成 .glb（InstancedMesh 走
//      EXT_mesh_gpu_instancing，Godot 4 匯入時自動變 MultiMesh）
//   4. 傳送光點（userData.portalGlow）座標、遊戲碰撞箱、playSize
//      另存 <id>.meta.json；mapRegistry 全表存 mapRegistry.json
//
// 產物全部放 godot/（Godot 專案根目錄）：
//   godot/blockout/<id>.glb
//   godot/data/<id>.meta.json
//   godot/data/mapRegistry.json
//
// 用法： node tools/export-godot.mjs [mapId ...]   （不帶參數 = 全部已建成的圖）

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PORT = 5607;
const OUT_BLOCKOUT = path.join(ROOT, 'godot', 'blockout');
const OUT_DATA = path.join(ROOT, 'godot', 'data');
fs.mkdirSync(OUT_BLOCKOUT, { recursive: true });
fs.mkdirSync(OUT_DATA, { recursive: true });

/* ── 傳送點 → 目的地 ─────────────────────────────────────────── */
// 光點座標抓得到，但「通往哪張圖」寫在各地圖檔的程式邏輯裡，抓不到。
// 這張表按各圖 makePortalGlow 的**建立順序**列目的地（scene.traverse 是
// DFS + add 順序，跟建立順序一致）。改地圖的傳送點時記得同步這裡——
// 數量對不上時下面會吵。
const PORTAL_TARGETS = {
  shrine: ['trail'],
  trail: ['shrine', 'village', 'bamboo', 'sunflower'],   // trail.js:426-429
  village: ['trail', 'kourindou'],                        // village.js:1591,1593
  bamboo: ['trail', 'eientei', 'namelessHill'],           // bamboo.js:1169-1171 北/南/東
  eientei: ['bamboo'],
  namelessHill: ['bamboo', 'sunflower'],                  // 西/東
  sunflower: ['namelessHill', 'trail'],                   // 西/北
  kourindou: ['village'],   // forest 未建成，西口的光點不會生成（kourindou.js:628）
};

/* ── 找 Chromium ─────────────────────────────────────────────── */
function findChromium() {
  const LA = process.env.LOCALAPPDATA ?? '';
  const candidates = [
    process.env.CHROMIUM_PATH,
    // Windows：Chrome，再不行用 Edge（每台 Windows 都有，本體就是 Chromium）
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
    LA && path.join(LA, 'Google\\Chrome\\Application\\chrome.exe'),
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
    // macOS
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
    // Linux
    '/opt/pw-browsers/chromium',
    '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome',
  ].filter(Boolean);
  for (const c of candidates) {
    try {
      const st = fs.statSync(c);
      if (st.isFile()) return c;
      if (st.isDirectory()) {
        for (const sub of ['chrome-linux/chrome', 'chrome']) {
          const p = path.join(c, sub);
          if (fs.existsSync(p)) return p;
        }
      }
    } catch { /* 下一個 */ }
  }
  // /opt/pw-browsers/chromium-*/chrome-linux/chrome
  const base = '/opt/pw-browsers';
  if (fs.existsSync(base)) {
    for (const d of fs.readdirSync(base)) {
      const p = path.join(base, d, 'chrome-linux', 'chrome');
      if (/^chromium-\d+$/.test(d) && fs.existsSync(p)) return p;
    }
  }
  throw new Error('找不到 Chrome / Edge / Chromium —— 可設 CHROMIUM_PATH 環境變數指向瀏覽器執行檔');
}

/* ── dev server ──────────────────────────────────────────────── */
function startServer() {
  const child = spawn(process.execPath, ['tools/dev-server.mjs', '.', String(PORT)], {
    cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stderr.on('data', (d) => process.stderr.write(`[dev-server] ${d}`));
  return new Promise((resolve, reject) => {
    child.stdout.on('data', () => resolve(child));   // 有輸出就當作起來了
    child.on('exit', (code) => reject(new Error(`dev-server 掛了 (${code})`)));
    setTimeout(() => resolve(child), 1500);
  });
}

/* ── 主流程 ──────────────────────────────────────────────────── */
const { chromium } = await import('playwright-core');

const server = await startServer();
const browser = await chromium.launch({
  executablePath: findChromium(),
  // 無頭環境沒有 GPU：SwiftShader 軟體算 WebGL2
  args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader',
         '--disable-gpu-sandbox', '--no-sandbox'],
});

try {
  const page = await browser.newPage({ viewport: { width: 640, height: 480 } });
  page.on('pageerror', (e) => console.error('  [page error]', e.message));

  /* 1) mapRegistry 全表 → JSON（用瀏覽器 import，省得 node 端解 ESM 相依） */
  await page.goto(`http://localhost:${PORT}/maps/trail/`, { waitUntil: 'domcontentloaded' });
  const registry = await page.evaluate(async () => {
    const m = await import('/src/world/mapRegistry.js');
    return JSON.parse(JSON.stringify(m.MAP_REGISTRY));
  });
  fs.writeFileSync(path.join(OUT_DATA, 'mapRegistry.json'), JSON.stringify(registry, null, 2));
  console.log(`mapRegistry.json：${Object.keys(registry).length} 張圖（含未建成）`);

  const wanted = process.argv.slice(2);
  const builtIds = Object.values(registry)
    .filter((m) => m.built && m.entry)
    .map((m) => m.id)
    .filter((id) => wanted.length === 0 || wanted.includes(id));

  for (const id of builtIds) {
    const entry = registry[id].entry.replace(/index\.html$/, '');
    const url = `http://localhost:${PORT}/${entry === '' ? '' : entry}`;
    process.stdout.write(`${id.padEnd(14)} ${url}  烘焙中…`);
    const t0 = Date.now();

    await page.goto(url, { waitUntil: 'load' });
    await page.waitForFunction(
      () => window.__godotExport && window.__godotExport.world.children.length > 0,
      null, { timeout: 60000 },
    );
    // 讓建圖後的合併 / 貼圖生成收尾
    await page.waitForTimeout(500);

    const result = await page.evaluate(async (vertCapArg) => {
      const { GLTFExporter } = await import('/vendor/jsm/exporters/GLTFExporter.js');
      const { mergeGeometries } = await import('/vendor/jsm/utils/BufferGeometryUtils.js');
      const { scene, world, colliders, THREE } = window.__godotExport;

      // Godot 4.4 的 glTF 匯入器不支援 EXT_mesh_gpu_instancing（會整檔拒收），
      // 所以 InstancedMesh 在這裡先展開：每個 instance 套上自己的矩陣後
      // 合併成一顆普通 Mesh。instanceColor 烤進頂點色。
      //
      // 頂點預算：花海這種圖展開後會衝到六百多萬頂點（.glb 300MB+）。
      // 底稿的用途是佈局參考，不是成品 —— 超過預算就把 instance 均勻抽稀，
      // 密度打折但空間分佈不變。可用 EXPORT_VERT_CAP 覆寫（0 = 不設限）。
      const VERT_CAP = vertCapArg;
      const toExpand = [];
      world.traverse((o) => { if (o.isInstancedMesh) toExpand.push(o); });
      let projected = 0;
      for (const im of toExpand) projected += im.count * im.geometry.attributes.position.count;
      const keepRatio = (VERT_CAP > 0 && projected > VERT_CAP) ? VERT_CAP / projected : 1;
      let expandedVerts = 0;
      for (const im of toExpand) {
        const geos = [];
        const m4 = new THREE.Matrix4();
        const col = new THREE.Color();
        const baseVerts = im.geometry.attributes.position.count;
        const stride = 1 / keepRatio;
        for (let k = 0; k < im.count; k += stride) {
          const i = Math.floor(k);
          im.getMatrixAt(i, m4);
          const g = im.geometry.clone();
          g.applyMatrix4(m4);
          if (im.instanceColor) {
            im.getColorAt(i, col);
            const arr = new Float32Array(baseVerts * 3);
            for (let j = 0; j < baseVerts; j++) {
              arr[j * 3] = col.r; arr[j * 3 + 1] = col.g; arr[j * 3 + 2] = col.b;
            }
            g.setAttribute('color', new THREE.BufferAttribute(arr, 3));
          }
          geos.push(g);
        }
        const merged = mergeGeometries(geos, false);
        expandedVerts += merged.attributes.position.count;
        const mat = im.material?.clone?.() ?? im.material;
        if (im.instanceColor && mat) mat.vertexColors = true;
        const mesh = new THREE.Mesh(merged, mat);
        mesh.name = (im.name || 'instanced') + '-expanded';
        mesh.position.copy(im.position);
        mesh.quaternion.copy(im.quaternion);
        mesh.scale.copy(im.scale);
        mesh.castShadow = im.castShadow;
        mesh.receiveShadow = im.receiveShadow;
        im.parent.add(mesh);
        im.parent.remove(im);
      }

      // 傳送光點：記座標，然後藏起來不進 glb（那是遊戲物件，不是場景幾何）
      const portals = [];
      const glows = [];
      scene.traverse((o) => { if (o.userData?.portalGlow) glows.push(o); });
      for (const g of glows) {
        portals.push({ x: +g.position.x.toFixed(2), y: +g.position.y.toFixed(2), z: +g.position.z.toFixed(2) });
        g.visible = false;
      }

      // 名牌 sprite（萬一混在 world）也不要
      const hidden = [];
      world.traverse((o) => { if (o.isSprite && o.visible) { o.visible = false; hidden.push(o); } });

      const exporter = new GLTFExporter();
      const glb = await exporter.parseAsync(world, { binary: true, onlyVisible: true });

      for (const g of glows) g.visible = true;
      for (const o of hidden) o.visible = true;

      // ArrayBuffer → base64（分塊，避免一次 apply 太長）
      const bytes = new Uint8Array(glb);
      let bin = '';
      for (let i = 0; i < bytes.length; i += 0x8000) {
        bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
      }

      let meshes = 0;
      world.traverse((o) => { if (o.isMesh) meshes++; });
      return { b64: btoa(bin), portals, colliders: JSON.parse(JSON.stringify(colliders)),
               meshes, expanded: toExpand.length, expandedVerts, keepRatio };
    }, Number(process.env.EXPORT_VERT_CAP ?? 2_000_000));

    const glbPath = path.join(OUT_BLOCKOUT, `${id}.glb`);
    fs.writeFileSync(glbPath, Buffer.from(result.b64, 'base64'));
    const targets = PORTAL_TARGETS[id] ?? [];
    if (targets.length !== result.portals.length) {
      console.warn(`\n  ⚠ ${id}：抓到 ${result.portals.length} 個光點，但 PORTAL_TARGETS 列了 ${targets.length} 個 —— 對照表要更新`);
    }
    result.portals.forEach((p, i) => { p.target = targets[i] ?? null; });
    const meta = {
      id,
      playSize: registry[id].playSize,
      safe: registry[id].safe,
      mobTheme: registry[id].mobTheme,
      connections: registry[id].connections,
      // three / glTF / Godot 都是右手系 y-up、-Z 朝前 —— 座標原樣通用，
      // 不需要任何軸轉換（Godot 匯入 glTF 不翻軸）。
      portals: result.portals,
      colliders: result.colliders,
    };
    fs.writeFileSync(path.join(OUT_DATA, `${id}.meta.json`), JSON.stringify(meta, null, 2));

    const mb = (fs.statSync(glbPath).size / 1048576).toFixed(1);
    const thinned = result.keepRatio < 1 ? `、抽稀至 ${(result.keepRatio * 100).toFixed(0)}%` : '';
    console.log(` ${mb}MB，${result.meshes} meshes（展開 ${result.expanded} 個 instanced、` +
      `${(result.expandedVerts / 1000).toFixed(0)}k 頂點${thinned}）、` +
      `${result.portals.length} 傳送點、${result.colliders.length} 碰撞箱，${((Date.now() - t0) / 1000).toFixed(1)}s`);
  }

  console.log('完成 →', path.relative(ROOT, OUT_BLOCKOUT));
} finally {
  await browser.close();
  server.kill();
}
