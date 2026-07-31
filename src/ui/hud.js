// 全地圖共用的 HUD —— 樣式與結構都由這裡注入，任何一張地圖長得都一樣。
//
// 之前神社與獸道各自在自己的 HTML 裡抄一份 HUD，結果字級、間距、
// 提示列位置全都對不上。現在只有這一份：新地圖只要 installHUD({...})，
// 版面就自動跟其他地圖一致。頁面自己的東西（選角畫面、任務面板、
// 場景編輯器）才留在各自的 HTML。
//
// 提供的元素：
//   #cross 準心              #place 右上角地名/時刻/畫質/等級
//   #prompt 互動提示          #toast 短訊
//   #help 左下操作提示列       #formBanner/#combo/#charge 戰鬥 HUD
//   #escMenu ESC 選單         #mapLoading 讀取畫面

const CSS = `
#hud { position:fixed; inset:0; pointer-events:none; z-index:10; }

#cross { position:absolute; left:50%; top:50%; width:18px; height:18px;
  transform:translate(-50%,-50%); opacity:.55; }
#cross:before, #cross:after { content:""; position:absolute; background:#fff;
  box-shadow:0 0 3px rgba(0,0,0,.8); }
#cross:before { left:50%; top:0; width:1.5px; height:100%; transform:translateX(-50%); }
#cross:after { top:50%; left:0; height:1.5px; width:100%; transform:translateY(-50%); }

/* 操作提示列。鍵名與說明之間只留一個小空隙 —— 以前用 min-width 撐成
   固定欄寬，「R          收刀」中間會空一大段，很難讀。 */
#help { position:absolute; left:16px; bottom:14px; color:#fff; font-size:12.5px;
  line-height:1.9; text-shadow:0 1px 4px rgba(0,0,0,.9); opacity:.85; }
#help .k { display:inline-block; margin-right:14px; white-space:nowrap; }
#help b { color:#ffd9a0; font-weight:600; margin-right:4px; }

#place { position:absolute; right:18px; top:16px; text-align:right; color:#fff;
  text-shadow:0 2px 8px rgba(0,0,0,.9); }
#place .jp { font-size:26px; letter-spacing:.32em; font-weight:600; text-indent:.32em; }
#place .sub { font-size:11px; letter-spacing:.22em; opacity:.7; margin-top:2px; }
#place .tod { font-size:11px; letter-spacing:.14em; opacity:.6; margin-top:6px; }
#place .lvl { font-size:11px; letter-spacing:.14em; color:#ffd9a0; opacity:.85; margin-top:6px; }

#prompt { position:absolute; left:50%; top:58%; transform:translateX(-50%);
  color:#fff; font-size:14px; letter-spacing:.06em; padding:7px 16px;
  background:rgba(20,14,24,.62); border:1px solid rgba(255,255,255,.22);
  border-radius:3px; text-shadow:0 1px 3px #000; opacity:0; transition:opacity .18s; }
#prompt.on { opacity:1; }

#toast { position:absolute; left:50%; top:66%; transform:translateX(-50%);
  color:#ffe9c9; font-size:13px; letter-spacing:.08em; opacity:0;
  text-shadow:0 1px 6px #000; transition:opacity .4s; white-space:nowrap; }
#toast.on { opacity:1; }

/* 戰鬥 HUD（只有帶技能的角色會用到，其餘角色由 combatHUD 隱藏） */
#formBanner{position:fixed;top:22%;left:50%;transform:translateX(-50%);z-index:55;
  font-size:30px;font-weight:800;letter-spacing:.22em;pointer-events:none;opacity:0;
  color:#ffb050;text-shadow:0 0 18px rgba(255,122,26,.85),0 0 40px rgba(58,122,255,.5),0 2px 6px rgba(0,0,0,.7)}
#formBanner.on{animation:formFlash .9s cubic-bezier(.2,.8,.3,1) forwards}
@keyframes formFlash{
  0%{opacity:0;transform:translateX(-50%) scale(1.35)}
  14%{opacity:1;transform:translateX(-50%) scale(1)}
  70%{opacity:1}
  100%{opacity:0;transform:translateX(-50%) scale(.96)}}
#combo{position:fixed;top:26%;right:5%;z-index:55;pointer-events:none;opacity:0;
  transition:opacity .35s;text-align:right;color:#ffd9a0;
  text-shadow:0 0 14px rgba(255,122,26,.7),0 2px 5px rgba(0,0,0,.7)}
#combo.on{opacity:1}
#combo .n{display:block;font-size:44px;font-weight:800;line-height:1}
#combo .u{display:block;font-size:12px;letter-spacing:.4em;margin-top:4px;color:#c9a2c8}
#combo.tick .n{animation:comboTick .22s ease-out}
@keyframes comboTick{0%{transform:scale(1.28)}100%{transform:scale(1)}}
#charge{position:fixed;bottom:16%;left:50%;transform:translateX(-50%);z-index:55;
  width:220px;height:5px;border-radius:3px;pointer-events:none;opacity:0;
  background:rgba(12,10,16,.62);box-shadow:0 0 0 1px rgba(255,176,80,.28);
  transition:opacity .18s}
#charge.on{opacity:1}
#charge .f{height:100%;width:0;border-radius:3px;
  background:linear-gradient(90deg,#ff7a1a,#3a7aff);
  box-shadow:0 0 12px rgba(255,122,26,.8)}
#charge .lb{position:absolute;top:-20px;left:0;width:100%;text-align:center;
  font-size:11px;letter-spacing:.34em;color:#ffc689;opacity:0;
  text-shadow:0 0 10px rgba(255,122,26,.8)}
#charge.full .lb{opacity:1}
#charge.full .f{animation:chargeFull .5s ease-out infinite alternate}
@keyframes chargeFull{0%{filter:brightness(1)}100%{filter:brightness(1.9)}}

/* ESC 選單 */
#escMenu { position:fixed; inset:0; z-index:70; display:none;
  align-items:center; justify-content:center;
  background:rgba(8,6,12,.72); backdrop-filter:blur(3px); }
#escMenu.on { display:flex; }
#escMenu .panel { min-width:260px; padding:26px 30px; text-align:center;
  background:linear-gradient(180deg,rgba(26,20,30,.96),rgba(14,10,18,.98));
  border:1px solid rgba(217,178,106,.34); border-radius:5px; }
#escMenu h3 { font-size:13px; letter-spacing:.34em; color:#d9b26a;
  font-weight:700; margin-bottom:18px; text-indent:.34em; }
#escMenu button { display:block; width:100%; margin:8px 0; padding:11px 18px;
  font-family:inherit; font-size:13.5px; letter-spacing:.16em; cursor:pointer;
  color:#f3ece4; background:rgba(255,255,255,.05);
  border:1px solid rgba(255,255,255,.2); border-radius:3px; transition:.15s; }
#escMenu button:hover { background:rgba(194,56,47,.28); border-color:#c2382f; }
#escMenu .hintline { margin-top:14px; font-size:10.5px; letter-spacing:.12em; color:#8d7f94; }
#escMenu .settings { margin-top:16px; padding-top:14px;
  border-top:1px solid rgba(255,255,255,.12); }
#escMenu .srow { display:flex; align-items:center; gap:8px; margin:7px 0; }
#escMenu .srow .lb { flex:0 0 52px; text-align:left; font-size:11.5px;
  letter-spacing:.18em; color:#a99cb0; }
#escMenu .srow button { flex:1; margin:0; padding:8px 10px; font-size:12px;
  letter-spacing:.1em; }

/* 換地圖時的讀取畫面 */
#mapLoading { position:fixed; inset:0; z-index:80; display:none;
  flex-direction:column; align-items:center; justify-content:center;
  background:#0b0d18; color:#e8dcc8; }
#mapLoading.on { display:flex; }
#mapLoading .t { font-size:22px; letter-spacing:.42em; text-indent:.42em; font-weight:600; }
#mapLoading .s { margin-top:12px; font-size:11px; letter-spacing:.34em; opacity:.5; }
`;

/**
 * 把共用 HUD 裝到頁面上。
 * @param {object} opts
 * @param {string} opts.title    右上角地名（例：博麗神社）
 * @param {string} opts.subtitle 地名下的英文（例：HAKUREI SHRINE）
 * @param {Array<[string,string]>} [opts.keys] 操作提示 [鍵, 說明]
 * @param {Array<[string,string]>} [opts.flyKeys] 飛行相關提示（角色會飛才顯示）
 * @param {Array<[string,string]>} [opts.combatKeys] 戰鬥操作提示（有技能才顯示）
 * @returns {object} 常用元素與 toast/prompt 工具
 */
export function installHUD({ title, subtitle, keys = [], flyKeys = [], combatKeys = [] }) {
  const style = document.createElement('style');
  style.textContent = CSS;
  document.head.appendChild(style);

  const keyHtml = (list) => list.map(([k, d]) => `<span class="k"><b>${k}</b>${d}</span>`).join('');

  const wrap = document.createElement('div');
  wrap.innerHTML = `
    <div id="hud">
      <div id="cross"></div>
      <div id="place">
        <div class="jp">${title}</div>
        <div class="sub">${subtitle}</div>
        <div class="tod" id="todLabel"></div>
        <div class="tod" id="qualLabel"></div>
        <div class="lvl" id="lvlBadge"></div>
      </div>
      <div id="prompt"></div>
      <div id="toast"></div>
      <div id="help">
        <div>${keyHtml(keys)}<span id="flyHelp">${keyHtml(flyKeys)}</span></div>
        <div id="combatHelp" style="display:none">${keyHtml(combatKeys)}</div>
      </div>
    </div>
    <div id="formBanner"></div>
    <div id="combo"><span class="n">0</span><span class="u">連擊</span></div>
    <div id="charge"><div class="lb">日之呼吸・全型</div><div class="f"></div></div>
    <div id="escMenu">
      <div class="panel">
        <h3>選 單</h3>
        <button id="escResume">繼續遊戲</button>
        <button id="escChar">回到標題畫面</button>
        <div class="settings">
          <div class="srow"><span class="lb">畫質</span><button id="escQuality">—</button></div>
          <div class="srow"><span class="lb">天氣</span><button id="escWeather">切換天氣</button></div>
          <div class="srow"><span class="lb">時刻</span><button id="escTime">快轉 3 小時</button><button id="escFlow">—</button></div>
        </div>
        <div class="hintline">ESC 關閉選單</div>
      </div>
    </div>
    <div id="mapLoading"><div class="t"></div><div class="s">LOADING</div></div>`;
  while (wrap.firstElementChild) document.body.appendChild(wrap.firstElementChild);

  const promptEl = document.getElementById('prompt');
  const toastEl = document.getElementById('toast');
  let toastTimer;

  return {
    promptEl, toastEl,
    todLabel: document.getElementById('todLabel'),
    qualLabel: document.getElementById('qualLabel'),
    escMenu: document.getElementById('escMenu'),

    toast(msg, dur = 2400) {
      toastEl.textContent = msg;
      toastEl.classList.add('on');
      clearTimeout(toastTimer);
      toastTimer = setTimeout(() => toastEl.classList.remove('on'), dur);
    },
    prompt(text) {
      if (text) { promptEl.textContent = text; promptEl.classList.add('on'); }
      else promptEl.classList.remove('on');
    },
    /** 戰鬥提示只給有技能的角色看 */
    showCombatKeys(on) {
      const el = document.getElementById('combatHelp');
      if (el) el.style.display = on ? '' : 'none';
    },
    /** 飛行提示只給會飛的角色看（緣一不會飛，就別給他看 F 飛行） */
    showFlyKeys(on) {
      const el = document.getElementById('flyHelp');
      if (el) el.style.display = on ? '' : 'none';
    },
    /** 換地圖前蓋上讀取畫面（避免看到別張圖的選角畫面閃過） */
    showLoading(text) {
      const el = document.getElementById('mapLoading');
      if (!el) return;
      el.querySelector('.t').textContent = text;
      el.classList.add('on');
    },
    hideLoading() {
      document.getElementById('mapLoading')?.classList.remove('on');
    },
  };
}

/**
 * ESC 選單：開關 + 「回到選角畫面」+ 畫質/天氣/時刻設定。
 * 每張地圖都掛這個，行為與版面一致 —— 之後的新圖也一樣。
 * @param {object} opts
 * @param {() => object|null} opts.getCtrl
 * @param {() => boolean} [opts.isBusy] 對話中/編輯器開著時 ESC 另有用途
 * @param {() => void} opts.onBackToSelect 回選角畫面要做什麼（各圖不同）
 * @param {import('../world/environment.js').Environment} [opts.env] 天氣/時刻鈕接這裡
 * @param {{get:()=>string, cycle:()=>string}} [opts.quality]
 *        畫質鈕：get 回目前檔名、cycle 切下一檔並回新檔名。
 *        神社接自己的後製 QUALITY，其他圖接 src/world/quality.js 的 basic 檔。
 */
export function bindEscMenu({ getCtrl, isBusy = () => false, onBackToSelect, env, quality }) {
  const menu = document.getElementById('escMenu');
  if (!menu) return { get isOpen() { return false; }, close() {} };

  // --- 設定列 ---
  const qBtn = document.getElementById('escQuality');
  const wBtn = document.getElementById('escWeather');
  const tBtn = document.getElementById('escTime');
  const fBtn = document.getElementById('escFlow');
  const syncSettings = () => {
    if (qBtn) qBtn.textContent = quality ? `畫質：${quality.get()}` : '—';
    if (wBtn && env) wBtn.textContent = `切換天氣（現在：${env.weather.label}）`;
    if (fBtn && env) fBtn.textContent = env.timeFlowing ? '暫停時間' : '恢復流動';
  };
  if (quality && qBtn) qBtn.addEventListener('click', () => { quality.cycle(); syncSettings(); });
  else if (qBtn) qBtn.closest('.srow').style.display = 'none';
  if (env && wBtn) wBtn.addEventListener('click', () => { env.cycleWeather(); syncSettings(); });
  else if (wBtn) wBtn.closest('.srow').style.display = 'none';
  if (env && tBtn) {
    tBtn.addEventListener('click', () => { env.skipHours(3); syncSettings(); });
    fBtn?.addEventListener('click', () => { env.timeFlowing = !env.timeFlowing; syncSettings(); });
  } else if (tBtn) tBtn.closest('.srow').style.display = 'none';

  const state = { isOpen: false };
  const open = () => {
    state.isOpen = true;
    syncSettings();
    menu.classList.add('on');
    const c = getCtrl();
    if (c) c.enabled = false;
    if (document.pointerLockElement) document.exitPointerLock();
  };
  const close = () => {
    state.isOpen = false;
    menu.classList.remove('on');
    const c = getCtrl();
    if (c) c.enabled = true;
  };

  document.getElementById('escResume')?.addEventListener('click', close);
  document.getElementById('escChar')?.addEventListener('click', () => {
    close();
    onBackToSelect();
  });

  window.addEventListener('keydown', (e) => {
    if (e.code !== 'Escape') return;
    if (state.isOpen) { close(); return; }
    if (isBusy()) return;          // 對話/編輯器自己處理 ESC
    open();
  });

  return {
    get isOpen() { return state.isOpen; },
    open, close,
  };
}
