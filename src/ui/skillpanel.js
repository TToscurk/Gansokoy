// 技能視窗（K）—— 楓之谷式的那一塊面板。
//
// 技能是**角色內建**的，不是某張地圖的功能，所以這個面板每張圖都掛，
// 跟地圖上有沒有怪無關。開著的時候會放開滑鼠鎖定（跟 ESC 選單同一套
// 規矩），關掉才能繼續操作。
//
// 內容分兩欄：左邊四個主動技（顯示消耗、冷卻、快捷鍵），右邊被動與
// 小技能。資料一律由 SkillSystem.panelState() 提供 —— 這裡不認識任何
// 一個技能的內容，加技能不用改這個檔。

const CSS = `
#skillPanel{position:fixed;inset:0;z-index:71;display:none;
  align-items:center;justify-content:center;
  background:rgba(8,6,12,.72);backdrop-filter:blur(3px)}
#skillPanel.on{display:flex}
#skillPanel .win{width:min(760px,92vw);max-height:86vh;overflow:auto;}
/* 預設白色捲軸在墨色面板上像貼了一條 OK 繃 —— 調成同色系（UI 審查 B2） */
#skillPanel .win::-webkit-scrollbar{width:8px}
#skillPanel .win::-webkit-scrollbar-track{background:rgba(255,255,255,.04)}
#skillPanel .win::-webkit-scrollbar-thumb{background:rgba(217,178,106,.35);border-radius:4px}
#skillPanel .win{scrollbar-width:thin;scrollbar-color:rgba(217,178,106,.35) rgba(255,255,255,.04);
  background:linear-gradient(180deg,rgba(28,22,32,.97),rgba(14,10,18,.99));
  border:1px solid rgba(217,178,106,.36);border-radius:6px;
  padding:22px 26px 24px}
#skillPanel h3{font-size:13px;letter-spacing:.34em;color:#d9b26a;
  padding-bottom:12px;border-bottom:1px solid rgba(255,255,255,.1);
  display:flex;justify-content:space-between;align-items:baseline}
#skillPanel h3 .lv{font-size:11px;letter-spacing:.2em;color:#9a8f7e}
#skillPanel .cols{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-top:16px}
@media (max-width:640px){#skillPanel .cols{grid-template-columns:1fr}}
#skillPanel h4{font-size:11px;letter-spacing:.28em;color:#b9a88c;margin-bottom:10px}

#skillPanel .row{display:flex;gap:11px;padding:9px 10px;margin-bottom:7px;
  border-radius:4px;background:rgba(255,255,255,.035);
  border:1px solid rgba(255,255,255,.07)}
#skillPanel .row.ready{border-color:rgba(255,176,80,.45)}
#skillPanel .row.locked{opacity:.4}
#skillPanel .ico{flex:0 0 40px;height:40px;border-radius:4px;position:relative;
  background:linear-gradient(160deg,#3a2c22,#1c1420);
  box-shadow:inset 0 0 0 1px rgba(217,178,106,.3);
  display:flex;align-items:center;justify-content:center;
  font-size:15px;font-weight:700;color:#ffc689}
#skillPanel .row.passive .ico{background:linear-gradient(160deg,#22303a,#141a22);
  box-shadow:inset 0 0 0 1px rgba(140,190,220,.3);color:#a8d4ec;font-size:11px}
#skillPanel .ico .cdo{position:absolute;left:0;bottom:0;width:100%;
  background:rgba(6,4,10,.76);border-radius:0 0 4px 4px}
#skillPanel .meta{flex:1;min-width:0}
#skillPanel .nm{font-size:12.5px;color:#f0e6d4;letter-spacing:.06em}
#skillPanel .en{font-size:9px;letter-spacing:.22em;color:#8f8672;margin-top:1px}
#skillPanel .ds{font-size:11px;color:#b8ae9e;margin-top:5px;line-height:1.5}
#skillPanel .cost{font-size:10.5px;color:#8fc4e8;margin-top:4px;letter-spacing:.08em}
#skillPanel .cost .cd{color:#d9b26a;margin-left:10px}
#skillPanel .tag{display:inline-block;font-size:9px;letter-spacing:.16em;
  padding:1px 6px;border-radius:2px;margin-left:6px;
  background:rgba(140,190,220,.16);color:#a8d4ec}
#skillPanel .hint{margin-top:16px;padding-top:12px;font-size:10.5px;color:#8f8672;
  letter-spacing:.14em;border-top:1px solid rgba(255,255,255,.08);text-align:center}
`;

/**
 * 掛上技能視窗。
 * @param {object} deps
 * @param {() => import('../combat/skills.js').SkillSystem|null} deps.getSkills
 * @param {() => object|null} deps.getCtrl  PlayerController（開面板要放開滑鼠）
 * @param {() => boolean} [deps.isBlocked]  對話中之類不該開面板的時機
 * @returns {{isOpen:boolean, open():void, close():void, toggle():void}}
 */
export function installSkillPanel({ getSkills, getCtrl, isBlocked = () => false }) {
  const style = document.createElement('style');
  style.textContent = CSS;
  document.head.appendChild(style);

  const el = document.createElement('div');
  el.id = 'skillPanel';
  el.innerHTML = `<div class="win">
    <h3><span>技　能</span><span class="lv"></span></h3>
    <div class="cols">
      <div><h4>主 動 技</h4><div class="actives"></div></div>
      <div><h4>被 動 ・ 小 技 能</h4><div class="passives"></div></div>
    </div>
    <div class="hint">K　關閉　／　1 ~ 4　使用主動技</div>
  </div>`;
  document.body.appendChild(el);

  const activesEl = el.querySelector('.actives');
  const passivesEl = el.querySelector('.passives');
  const lvEl = el.querySelector('.lv');

  const render = () => {
    const sk = getSkills();
    if (!sk) {
      activesEl.innerHTML = '<div class="ds">這位角色沒有戰鬥技能。</div>';
      passivesEl.innerHTML = '';
      lvEl.textContent = '';
      return;
    }
    const st = sk.panelState();
    lvEl.textContent = `Lv.${st.level}`;

    activesEl.innerHTML = st.actives.map(s => {
      // 冷卻遮罩由下往上蓋住圖示，跟快捷列同一個讀法
      const cdPct = s.cdMax > 0 ? Math.min(100, (s.cd / s.cdMax) * 100) : 0;
      return `
      <div class="row ${s.locked ? 'locked' : (s.ready ? 'ready' : '')}">
        <div class="ico">${s.slot}
          <div class="cdo" style="height:${cdPct}%"></div>
        </div>
        <div class="meta">
          <div class="nm">${s.zh}</div>
          <div class="en">${s.en}</div>
          <div class="ds">${s.desc}</div>
          <div class="cost">氣力 ${s.mp}<span class="cd">冷卻 ${s.cdMax}s</span></div>
        </div>
      </div>`;
    }).join('');

    passivesEl.innerHTML = st.passives.map(p => `
      <div class="row passive ${p.locked ? 'locked' : ''}">
        <div class="ico">${p.minor ? '小' : '被'}</div>
        <div class="meta">
          <div class="nm">${p.zh}${p.minor ? '<span class="tag">小技能</span>' : ''}</div>
          <div class="en">${p.en}</div>
          <div class="ds">${p.desc}</div>
        </div>
      </div>`).join('');
  };

  const api = {
    isOpen: false,
    open() {
      if (isBlocked()) return;
      render();
      el.classList.add('on');
      api.isOpen = true;
      // 跟 ESC 選單同一套規矩：面板開著時放開滑鼠，不然轉不了視角也點不到東西
      const ctrl = getCtrl();
      if (ctrl?.locked) document.exitPointerLock?.();
    },
    close() {
      el.classList.remove('on');
      api.isOpen = false;
    },
    toggle() { api.isOpen ? api.close() : api.open(); },
  };

  window.addEventListener('keydown', (e) => {
    if (e.code === 'KeyK') {
      if (isBlocked() && !api.isOpen) return;
      e.preventDefault();
      api.toggle();
    } else if (e.code === 'Escape' && api.isOpen) {
      e.preventDefault();
      api.close();
    }
  });

  return api;
}
