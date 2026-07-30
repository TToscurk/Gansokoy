// 角色場景編輯器 —— 面板列出還沒上場的角色，可以拖到 3D 場景裡放置；
// 已經在場上的角色可以直接在場景裡拖曳搬移，或拖回面板收回。
//
// 純粹是 shrine-spawn.js 的 place()/unplace()/getPlacements() 的操作介面，
// 不自己保存任何狀態 —— 狀態表本身活在 entities/placements.js（本次遊玩
// 期間有效，重新整理頁面就歸零）。
import * as THREE from 'three';
import { ROSTER } from '../entities/roster.js';

const UP = new THREE.Vector3(0, 1, 0);
const hex = (n) => '#' + n.toString(16).padStart(6, '0');

export class SceneEditor {
  /**
   * @param {object} deps
   * @param {THREE.Scene} deps.scene
   * @param {THREE.Camera} deps.camera
   * @param {THREE.WebGLRenderer} deps.renderer
   * @param {THREE.Object3D} deps.world        地形／建築的共同父物件，拖放時的 raycast 目標
   * @param {(x:number,z:number)=>number} deps.heightAt
   * @param {ReturnType<import('../entities/shrine-spawn.js').spawnAllNPCs>} deps.npcSystem
   * @param {() => string} deps.getPlayerId    目前玩家扮演的角色 id（會隨換角色改變，故用 getter）
   * @param {() => import('../player/controller.js').PlayerController|null} deps.getCtrl
   */
  constructor({ scene, camera, renderer, world, heightAt, npcSystem, getPlayerId, getCtrl }) {
    this.camera = camera;
    this.renderer = renderer;
    this.world = world;
    this.heightAt = heightAt;
    this.npcSystem = npcSystem;
    this.getPlayerId = getPlayerId;
    this.getCtrl = getCtrl;

    this.el = document.getElementById('sceneEditor');
    this.palette = this.el.querySelector('.epalette');

    this.isOpen = false;
    this._raycaster = new THREE.Raycaster();
    this._dragPlane = new THREE.Plane();
    this._drag = null;      // { id, rec }
    this._selected = null;  // 目前選取的角色（可用 Q/E 或滾輪轉向）

    this._bind();
  }

  open() {
    this.isOpen = true;
    this.el.classList.add('on');
    const ctrl = this.getCtrl();
    if (ctrl) ctrl.enabled = false;
    if (document.pointerLockElement) document.exitPointerLock();
    this._renderPalette();
  }

  close() {
    if (this._drag) this._commitDrag(this._drag, false);   // 收尾未完成的拖曳，落在原地
    this.isOpen = false;
    this.el.classList.remove('on');
    const ctrl = this.getCtrl();
    if (ctrl) ctrl.enabled = true;
  }

  toggle() {
    if (this.isOpen) this.close();
    else this.open();
  }

  /** 未上場清單：ROSTER 減去已有擺放的、減去玩家目前扮演的角色 */
  _renderPalette() {
    const placements = this.npcSystem.getPlacements();
    const playerId = this.getPlayerId();
    const unplaced = ROSTER.filter(s => !(s.id in placements) && s.id !== playerId);

    // 目前選取誰（可以轉向）——顯示在面板上，免得不知道 Q/E 會轉到誰
    const selEl = this.el.querySelector('.esel');
    if (selEl) {
      selEl.textContent = this._selected
        ? `已選取：${this._selected.spec.zh}　Q/E 旋轉（Shift 微調）`
        : '點一下場上的角色即可選取並旋轉';
    }

    if (!unplaced.length) {
      this.palette.innerHTML = '<div class="eempty">角色都已經在場上了。</div>';
      return;
    }

    this.palette.innerHTML = '';
    for (const spec of unplaced) {
      const card = document.createElement('div');
      card.className = 'ecard';
      card.draggable = true;
      card.dataset.id = spec.id;
      card.innerHTML =
        `<div class="eswatch" style="background:${hex(spec.palette.outfit)}"></div>
         <div class="enm">${spec.zh}</div>`;
      card.addEventListener('dragstart', (e) => {
        e.dataTransfer.setData('text/plain', spec.id);
        e.dataTransfer.effectAllowed = 'copy';
      });
      this.palette.appendChild(card);
    }
  }

  _bind() {
    const dom = this.renderer.domElement;

    // ---- 面板卡片拖到畫布上 = 放置 ----
    dom.addEventListener('dragover', (e) => {
      if (!this.isOpen) return;
      e.preventDefault();
      e.dataTransfer.dropEffect = 'copy';
    });
    dom.addEventListener('drop', (e) => {
      if (!this.isOpen) return;
      e.preventDefault();
      const id = e.dataTransfer.getData('text/plain');
      if (!id) return;
      const hit = this._raycastObject(e.clientX, e.clientY, this.world);
      if (!hit) return;
      this.npcSystem.place(id, hit.point.x, hit.point.z, 0);
      this._renderPalette();
    });

    // ---- 已上場角色：直接在畫布上拖曳搬移，或拖回面板收回 ----
    dom.addEventListener('pointerdown', (e) => {
      if (!this.isOpen || this._drag) return;
      const rec = this._pickNPC(e.clientX, e.clientY);
      if (!rec) return;
      e.preventDefault();
      this._drag = { id: rec.spec.id, rec, moved: false };
      this._selected = rec;                     // 點到誰就選誰，之後可以轉他
      this._dragPlane.setFromNormalAndCoplanarPoint(UP, rec.pos);
      dom.style.cursor = 'grabbing';
      this._renderPalette();
    });

    // ---- 3D 旋轉：選取角色後用 Q/E（或按住 Shift 滾輪）轉向 ----
    window.addEventListener('keydown', (e) => {
      if (!this.isOpen || !this._selected) return;
      let d = 0;
      if (e.code === 'KeyQ') d = -1;
      else if (e.code === 'KeyE') d = 1;
      else if (e.code === 'BracketLeft') d = -0.25;
      else if (e.code === 'BracketRight') d = 0.25;
      else return;
      e.preventDefault();
      this._rotate(this._selected, d * (e.shiftKey ? 0.06 : 0.20));
    });
    dom.addEventListener('wheel', (e) => {
      if (!this.isOpen || !this._selected || !e.shiftKey) return;
      e.preventDefault();
      this._rotate(this._selected, Math.sign(e.deltaY) * 0.12);
    }, { passive: false });

    window.addEventListener('pointermove', (e) => {
      if (!this._drag) return;
      const p = this._raycastPlane(e.clientX, e.clientY, this._dragPlane);
      if (!p) return;
      const { rec } = this._drag;
      const spec = rec.spec;
      const y = this.heightAt(p.x, p.z) + (spec.float ? (spec.floatY ?? 0.8) : 0) + (spec.sleep ? 0.3 : 0);
      rec.root.position.set(p.x, y, p.z);
      rec.plate.position.set(p.x, y + 2.35, p.z);
      rec.pos.set(p.x, y, p.z);
      // 貼著新高度更新拖曳平面，讓斜坡／台階邊緣也能跟手
      this._dragPlane.setFromNormalAndCoplanarPoint(UP, rec.pos);
    });

    window.addEventListener('pointerup', (e) => {
      if (!this._drag) return;
      const overPanel = this._pointInEl(e.clientX, e.clientY, this.el);
      this._commitDrag(this._drag, overPanel);
      dom.style.cursor = '';
      this._drag = null;
    });
  }

  /**
   * 轉一位已放置的角色（3D 旋轉），並立刻寫回擺放記錄。
   * NPCManager 每幀會把朝向拉回 baseYaw，所以要一起改 baseYaw，
   * 不然放開手角色就自己轉回去了。
   */
  _rotate(rec, delta) {
    rec.baseYaw = (rec.baseYaw ?? 0) + delta;
    rec.root.rotation.y = rec.baseYaw;
    this.npcSystem.place(rec.spec.id, rec.pos.x, rec.pos.z, rec.baseYaw);
  }

  /** 拖曳結束：落在面板上 = 收回，否則 = 在目前位置定案 */
  _commitDrag({ id, rec }, overPanel) {
    if (overPanel) {
      this.npcSystem.unplace(id);
      if (this._selected === rec) this._selected = null;
    } else {
      this.npcSystem.place(id, rec.pos.x, rec.pos.z, rec.baseYaw ?? 0);
    }
    this._renderPalette();
  }

  _pickNPC(clientX, clientY) {
    const ndc = this._ndc(clientX, clientY);
    if (!ndc) return null;
    this._raycaster.setFromCamera(ndc, this.camera);
    const roots = this.npcSystem.mgr.npcs.map(n => n.root);
    const hits = this._raycaster.intersectObjects(roots, true);
    if (!hits.length) return null;
    let obj = hits[0].object;
    while (obj && !obj.userData.npcId) obj = obj.parent;
    if (!obj) return null;
    return this.npcSystem.mgr.npcs.find(n => n.spec.id === obj.userData.npcId) ?? null;
  }

  _raycastObject(clientX, clientY, target) {
    const ndc = this._ndc(clientX, clientY);
    if (!ndc) return null;
    this._raycaster.setFromCamera(ndc, this.camera);
    const hits = this._raycaster.intersectObject(target, true);
    return hits.length ? hits[0] : null;
  }

  _raycastPlane(clientX, clientY, plane) {
    const ndc = this._ndc(clientX, clientY);
    if (!ndc) return null;
    this._raycaster.setFromCamera(ndc, this.camera);
    const out = new THREE.Vector3();
    return this._raycaster.ray.intersectPlane(plane, out) ? out : null;
  }

  _ndc(clientX, clientY) {
    const rect = this.renderer.domElement.getBoundingClientRect();
    const x = ((clientX - rect.left) / rect.width) * 2 - 1;
    const y = -((clientY - rect.top) / rect.height) * 2 + 1;
    if (x < -1 || x > 1 || y < -1 || y > 1) return null;
    return { x, y };
  }

  _pointInEl(clientX, clientY, el) {
    const r = el.getBoundingClientRect();
    return clientX >= r.left && clientX <= r.right && clientY >= r.top && clientY <= r.bottom;
  }
}
