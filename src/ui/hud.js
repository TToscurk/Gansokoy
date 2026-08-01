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

/* 玩家血量。左下角，橫條 + 數字。受擊時整條閃一下白。 */
#vitals{position:fixed;left:22px;bottom:96px;z-index:56;width:240px;
  transition:opacity .25s ease;
  pointer-events:none;opacity:0;transition:opacity .3s}
#vitals.on{opacity:1}
#vitals .lb{font-size:10.5px;letter-spacing:.32em;color:#e8b0a0;margin-bottom:5px;
  text-shadow:0 2px 5px rgba(0,0,0,.8)}
#vitals .bar{position:relative;height:9px;border-radius:5px;overflow:hidden;
  background:rgba(12,8,10,.7);box-shadow:0 0 0 1px rgba(230,120,100,.32)}
/* 掉血的殘影條：先掉一小段紅底，主條再追上來，打到多重才讀得出來 */
#vitals .ghost{position:absolute;inset:0;width:100%;border-radius:5px;
  background:rgba(210,70,60,.5);transition:width .5s ease-out .18s}
#vitals .f{position:absolute;inset:0;width:100%;border-radius:5px;
  background:linear-gradient(90deg,#d8452f,#f08a4a);
  box-shadow:0 0 12px rgba(216,69,47,.7);transition:width .16s ease-out}
#vitals.low .f{animation:hpLow .8s ease-in-out infinite alternate}
@keyframes hpLow{0%{filter:brightness(1)}100%{filter:brightness(1.75)}}
#vitals .mbar{position:relative;height:6px;border-radius:4px;overflow:hidden;margin-top:5px;
  background:rgba(8,10,16,.7);box-shadow:0 0 0 1px rgba(110,170,220,.3)}
#vitals .mf{position:absolute;inset:0;width:100%;border-radius:4px;
  background:linear-gradient(90deg,#2f6fbf,#5fb6e8);
  box-shadow:0 0 10px rgba(70,150,220,.6);transition:width .16s ease-out}
#vitals .n{margin-top:4px;font-size:11px;letter-spacing:.16em;color:#f0cdbc;
  text-shadow:0 2px 5px rgba(0,0,0,.8)}
#vitals .n .mp{color:#9fd0f0;margin-left:10px}
#vitals.hurt .bar{animation:hpHurt .22s ease-out}
@keyframes hpHurt{0%{transform:translateX(-4px)}50%{transform:translateX(4px)}100%{transform:translateX(0)}}

/* 受擊紅屏 */
#hurtFlash{position:fixed;inset:0;z-index:58;pointer-events:none;opacity:0;
  background:radial-gradient(ellipse at center,rgba(180,20,10,0) 42%,rgba(180,20,10,.62) 100%)}
#hurtFlash.on{animation:hurtFx .42s ease-out}
@keyframes hurtFx{0%{opacity:1}100%{opacity:0}}

/* 死亡黑幕 */
#deathVeil{position:fixed;inset:0;z-index:72;display:none;flex-direction:column;
  align-items:center;justify-content:center;background:rgba(8,4,6,.9);
  backdrop-filter:blur(2px)}
#deathVeil.on{display:flex}
#deathVeil .k{font-size:38px;letter-spacing:.5em;color:#d8452f;
  text-shadow:0 0 26px rgba(216,69,47,.7)}
#deathVeil .s{margin-top:14px;font-size:12px;letter-spacing:.34em;color:#b0a0a4}

/* 技能列。右下四格，冷卻用由下往上的遮罩掃過去。 */
#skills{position:fixed;right:22px;bottom:96px;z-index:56;display:flex;gap:8px;
  transition:opacity .25s ease;
  pointer-events:none;opacity:0;transition:opacity .3s}
#skills.on{opacity:1}
#skills .s{position:relative;width:52px;height:52px;border-radius:4px;overflow:hidden;
  background:linear-gradient(180deg,rgba(30,22,34,.9),rgba(16,12,20,.94));
  box-shadow:0 0 0 1px rgba(217,178,106,.3);text-align:center}
#skills .s .k{position:absolute;top:3px;left:0;width:100%;font-size:10px;
  letter-spacing:.1em;color:#d9b26a}
#skills .s .n{position:absolute;bottom:5px;left:0;width:100%;font-size:9px;
  letter-spacing:.06em;color:#e8dcc8;line-height:1.15;padding:0 2px}
/* 冷卻遮罩：高度 = 剩餘比例，由下往上退掉 */
#skills .s .cd{position:absolute;left:0;bottom:0;width:100%;height:0;
  background:rgba(6,4,10,.74)}
#skills .s .cdn{position:absolute;top:50%;left:0;width:100%;transform:translateY(-50%);
  font-size:15px;font-weight:700;color:#fff;opacity:0;
  text-shadow:0 2px 6px rgba(0,0,0,.9)}
#skills .s.cooling .cdn{opacity:1}
#skills .s.locked{filter:grayscale(1) brightness(.5)}
#skills .s.locked .n::after{content:attr(data-lv);display:block;color:#a08a6a}
#skills .s.ready{box-shadow:0 0 0 1px rgba(255,176,80,.75),0 0 14px rgba(255,122,26,.4)}
#skills .s.buffed{animation:skBuff .7s ease-in-out infinite alternate}
@keyframes skBuff{0%{box-shadow:0 0 0 1px rgba(120,200,255,.7)}
  100%{box-shadow:0 0 0 1px rgba(120,200,255,.9),0 0 20px rgba(120,200,255,.6)}}

/* 看穿要害 */
#critMark{position:fixed;top:38%;left:50%;transform:translateX(-50%);z-index:57;
  font-size:22px;letter-spacing:.5em;color:#bfe6ff;pointer-events:none;opacity:0;
  text-shadow:0 0 20px rgba(120,200,255,.9)}
#critMark.on{animation:critFx .5s ease-out}
@keyframes critFx{0%{opacity:1;transform:translateX(-50%) scale(1.3)}
  100%{opacity:0;transform:translateX(-50%) scale(1)}}

/* 對話中收起戰鬥 HUD —— 窄視窗（1024）下血條與技能鍵會疊在對話框上，
   而對話中本來就出不了招（isBlocked 擋掉了），顯示著只是干擾。
   #cross/#prompt 的同款規則在各圖的 index.html（dialogue.js 依賴的那組）。 */
body.talking #vitals, body.talking #skills, body.talking #questToasts {
  opacity:0 !important; pointer-events:none; }

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
  letter-spacing:.1em; white-space:nowrap; }

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
    <div id="vitals">
      <div class="lb">血　量</div>
      <div class="bar"><div class="ghost"></div><div class="f"></div></div>
      <div class="mbar"><div class="mf"></div></div>
      <div class="n"><span class="hp">0</span> / <span class="mx">0</span><span class="mp">氣 <span class="mpv">0</span> / <span class="mpmx">0</span></span></div>
    </div>
    <div id="skills"></div>
    <div id="critMark">看　穿</div>
    <div id="hurtFlash"></div>
    <div id="deathVeil"><div class="k">絶　命</div><div class="s">復 活 中 …</div></div>
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
    /**
     * 更新血量／氣力條。
     * @param {import('../player/vitals.js').Vitals} v
     * @param {boolean} [hurt] 這次是不是受擊造成的（接紅屏與震動）
     */
    vitals(v, hurt = false) {
      const el = document.getElementById('vitals');
      if (!el || !v) return;
      el.classList.add('on');
      const r = Math.max(0, Math.min(1, v.hp / v.max));
      const mr = Math.max(0, Math.min(1, v.mp / v.maxMp));
      el.querySelector('.f').style.width = (r * 100).toFixed(1) + '%';
      el.querySelector('.ghost').style.width = (r * 100).toFixed(1) + '%';
      el.querySelector('.mf').style.width = (mr * 100).toFixed(1) + '%';
      el.querySelector('.hp').textContent = Math.ceil(v.hp);
      el.querySelector('.mx').textContent = Math.round(v.max);
      el.querySelector('.mpv').textContent = Math.floor(v.mp);
      el.querySelector('.mpmx').textContent = Math.round(v.maxMp);
      el.classList.toggle('low', r < 0.3);
      if (hurt) {
        el.classList.remove('hurt');
        void el.offsetWidth;              // 重播 CSS 動畫
        el.classList.add('hurt');
        const fl = document.getElementById('hurtFlash');
        if (fl) { fl.classList.remove('on'); void fl.offsetWidth; fl.classList.add('on'); }
      }
    },
    /**
     * 技能列。傳 SkillSystem.hudState() 的結果。
     * 第一次呼叫時建 DOM，之後只改 class 與樣式 —— 這是每幀都會跑的。
     * @param {{slot:string,zh:string,en:string,locked:boolean,unlock:number,
     *          cd:number,cdMax:number,active:number}[]} list
     */
    skills(list) {
      const el = document.getElementById('skills');
      if (!el) return;
      if (el.children.length !== list.length) {
        el.innerHTML = list.map(s => `
          <div class="s"><div class="cd"></div>
            <div class="k">${s.slot}</div>
            <div class="cdn"></div>
            <div class="n"></div></div>`).join('');
      }
      el.classList.add('on');
      list.forEach((s, i) => {
        const d = el.children[i];
        const cooling = s.cd > 0.05;
        d.classList.toggle('locked', s.locked);
        d.classList.toggle('cooling', cooling && !s.locked);
        d.classList.toggle('ready', !s.locked && !cooling);
        d.classList.toggle('buffed', s.active > 0);
        // 技能名太長，取「・」後面那一段當短名（火車、輪迴…）
        const short = s.zh.includes('・') ? s.zh.split('・').pop() : s.zh;
        d.querySelector('.n').textContent = s.locked ? `Lv.${s.unlock}` : short;
        d.querySelector('.cd').style.height = cooling ? `${(s.cd / s.cdMax) * 100}%` : '0';
        d.querySelector('.cdn').textContent = cooling ? Math.ceil(s.cd) : '';
      });
    },
    /** 死亡黑幕（復活時再呼叫 false 收掉） */
    deathVeil(on) {
      document.getElementById('deathVeil')?.classList.toggle('on', on);
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
