// 對話框：逐字顯示，E / 左鍵推進，講完自動收起。

export class Dialogue {
  constructor() {
    this.el = document.getElementById('talk');
    this.elWho = this.el.querySelector('.who .n');
    this.elRomaji = this.el.querySelector('.who .r');
    this.elDot = this.el.querySelector('.who .dot');
    this.elLine = this.el.querySelector('.line');
    this.elNext = this.el.querySelector('.next');

    this.active = false;
    this.lines = [];
    this.index = 0;
    this.shown = '';
    this.full = '';
    this.charTimer = 0;
    this.onClose = null;
  }

  open(spec, lines, onClose) {
    this.active = true;
    this.lines = lines;
    this.index = 0;
    this.onClose = onClose;

    this.elWho.textContent = spec.zh;
    this.elRomaji.textContent = spec.title || spec.en;
    this.elDot.style.background = '#' + (spec.palette.accent).toString(16).padStart(6, '0');
    this.el.classList.add('on');
    document.body.classList.add('talking');
    this._setLine(lines[0]);
  }

  _setLine(text) {
    this.full = text;
    this.shown = '';
    this.charTimer = 0;
    this.elLine.textContent = '';
    this.elNext.style.opacity = '0';
  }

  /** 回傳 true 表示已關閉 */
  advance() {
    if (!this.active) return false;

    // 還在打字 → 直接全部顯示
    if (this.shown.length < this.full.length) {
      this.shown = this.full;
      this.elLine.textContent = this.shown;
      this.elNext.style.opacity = '1';
      return false;
    }

    this.index++;
    if (this.index >= this.lines.length) {
      this.close();
      return true;
    }
    this._setLine(this.lines[this.index]);
    return false;
  }

  close() {
    this.active = false;
    this.el.classList.remove('on');
    document.body.classList.remove('talking');
    this.onClose?.();
  }

  update(dt) {
    if (!this.active) return;
    if (this.shown.length >= this.full.length) return;
    this.charTimer += dt;
    const cps = 34;                       // 每秒字數
    while (this.charTimer > 1 / cps && this.shown.length < this.full.length) {
      this.charTimer -= 1 / cps;
      this.shown = this.full.slice(0, this.shown.length + 1);
    }
    this.elLine.textContent = this.shown;
    if (this.shown.length >= this.full.length) this.elNext.style.opacity = '1';
  }
}
