// 任務日誌面板 + toast 通知。純粹是 QuestManager 狀態的顯示層，
// 引擎（quests/manager.js）完全不知道 DOM 存在。

export class QuestLog {
  constructor(mgr) {
    this.mgr = mgr;
    this.el = document.getElementById('questLog');
    this.body = this.el.querySelector('.body');
    this.toasts = document.getElementById('questToasts');

    mgr.onToast = (text, kind) => this._toast(text, kind);
    mgr.onChange = () => this.render();
    this.render();
  }

  toggle() {
    this.el.classList.toggle('on');
    if (this.el.classList.contains('on')) this.render();
  }

  render() {
    const active = this.mgr.listActive();
    const done = this.mgr.listCompleted();

    let html = active.length
      ? active.map(q => `
          <div class="q${q.main ? ' main' : ''}">
            <div class="qt">${q.main ? '<span class="main-badge">主線</span>' : ''}${escapeHtml(q.title)}</div>
            <div class="qo">${escapeHtml(q.objective)}</div>
          </div>`).join('')
      : '<div class="empty">目前沒有進行中的任務。找幻想鄉的住民聊聊，也許會有事情找上妳。</div>';

    if (done.length) {
      html += '<div class="doneHead">已完成</div>'
        + done.map(t => `<div class="qdone">✓ ${escapeHtml(t)}</div>`).join('');
    }

    this.body.innerHTML = html;
  }

  _toast(text, kind) {
    const el = document.createElement('div');
    el.className = `qtoast ${kind}`;
    el.textContent = text;
    this.toasts.appendChild(el);
    // 用 rAF 讓 class 的加入落在下一幀，CSS transition 才會真的播放
    requestAnimationFrame(() => el.classList.add('on'));
    setTimeout(() => {
      el.classList.remove('on');
      setTimeout(() => el.remove(), 500);
    }, 3200);
  }
}

function escapeHtml(s) {
  return s.replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}
