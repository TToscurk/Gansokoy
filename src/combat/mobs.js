// 雜魚妖精群 —— 無雙手感的「草」。（自 gensokoy3d 移植，刷怪窩改為參數）
//
// 每窩刷 perNest 隻，身體與翅膀各一個 InstancedMesh。
// 妖精是無害的（幻想鄉的妖精本來就打不死、愛玩）：遊蕩、被砍會擊飛閃白、
// 「死」了化成光點，十幾秒後在窩裡重新凝聚 —— 呼應大妖精的台詞
// 「妖精是自然的一部分，死不了」。
//
// 哪張地圖有怪、怪在哪一段，由呼叫端用 nests 決定（絕對座標）——
// 神社境內不刷、獸道中段刷幾窩，之後的新地圖照樣傳自己的窩清單。

import * as THREE from 'three';
import { groundHeight } from '../world/terrain.js';
import { sectorHits, countAlive } from './mobcore.js';

const MOB_R = 0.55;        // 命中判定半徑
const DEAD = 2;            // state 2 = 消散中（mobcore 用它跳過已死的）
const RESPAWN = 12;        // 重生秒數
const HP = 40;

const FAIRY_COLORS = [0xa8e0ff, 0xffd0e8, 0xd0ffc8, 0xfff0b0, 0xe0d0ff];

export class FairyMobs {
  /**
   * @param {THREE.Scene} scene
   * @param {{x:number,z:number,r:number}[]} nests 刷怪窩（絕對座標 + 半徑）
   * @param {number} [perNest=8] 每窩幾隻
   */
  constructor(scene, nests, perNest = 8) {
    this.scene = scene;
    const NESTS = nests;
    const PER_NEST = perNest;
    const total = NESTS.length * PER_NEST;

    // 身體：拉長的小水滴。用不受光的 BasicMaterial —— 妖精本來就是
    // 發光的小東西，夜裡也看得見，還省下全圖最便宜的光照成本。
    const bodyGeo = new THREE.SphereGeometry(0.22, 10, 8);
    bodyGeo.scale(1, 1.35, 1);
    const bodyMat = new THREE.MeshBasicMaterial({ color: 0xffffff });
    this.bodies = new THREE.InstancedMesh(bodyGeo, bodyMat, total);
    this.bodies.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(total * 3), 3);
    this.bodies.frustumCulled = false;

    // 翅膀：左右兩片併成一個 X 形小面片
    const wingGeo = new THREE.PlaneGeometry(0.5, 0.3);
    wingGeo.rotateY(Math.PI / 4);
    const wingMat = new THREE.MeshBasicMaterial({
      color: 0xd0f0ff, transparent: true, opacity: 0.55,
      blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
    });
    this.wings = new THREE.InstancedMesh(wingGeo, wingMat, total * 2);
    this.wings.frustumCulled = false;

    scene.add(this.bodies, this.wings);

    // 實體狀態
    this.mobs = [];
    const col = new THREE.Color();
    let k = 0;
    for (const nest of NESTS) {
      const cx = nest.x, cz = nest.z;
      for (let i = 0; i < PER_NEST; i++) {
        const a = Math.random() * Math.PI * 2;
        const d = Math.random() * nest.r;
        const x = cx + Math.cos(a) * d, z = cz + Math.sin(a) * d;
        col.setHex(FAIRY_COLORS[(Math.random() * FAIRY_COLORS.length) | 0]);
        this.bodies.setColorAt(k, col);
        this.mobs.push({
          i: k, nest: { x: cx, z: cz, r: nest.r },
          pos: new THREE.Vector3(x, 0, z),
          vel: new THREE.Vector3(),
          hp: HP, state: 0,          // 0 遊蕩 1 擊飛 2 消散
          timer: Math.random() * 3,  // 遊蕩換向計時
          phase: Math.random() * Math.PI * 2,
          flash: 0,
          base: col.clone(),
        });
        k++;
      }
    }
    this.bodies.instanceColor.needsUpdate = true;

    this._m = new THREE.Matrix4();
    this._q = new THREE.Quaternion();
    this._s = new THREE.Vector3(1, 1, 1);
    this._e = new THREE.Euler();
    this._c = new THREE.Color();
    this.kills = 0;
  }

  /** 扇形判定：回傳被打中的存活 mob 陣列（共用 mobcore） */
  inSector(origin, yaw, range, arc) {
    return sectorHits(this.mobs, origin, yaw, range, arc, MOB_R, DEAD);
  }

  /** 造成傷害 + 擊飛。回傳是否擊殺。 */
  damage(m, dmg, dirX, dirZ) {
    m.hp -= dmg;
    m.flash = 1;
    const k = m.hp <= 0 ? 10 : 7;
    m.vel.set(dirX * k, m.hp <= 0 ? 6.5 : 4.2, dirZ * k);
    if (m.hp <= 0) {
      m.state = 2;
      m.timer = RESPAWN;
      this.kills++;
      return true;
    }
    m.state = 1;
    m.timer = 0.55;
    return false;
  }

  update(dt, t, playerPos) {
    const m4 = this._m, q = this._q, s = this._s, e = this._e, c = this._c;
    let colorDirty = false;

    for (const m of this.mobs) {
      const far = playerPos &&
        Math.abs(m.pos.x - playerPos.x) > 150 + 40 &&
        Math.abs(m.pos.z - playerPos.z) > 150 + 40;

      if (!far) {
        if (m.state === 0) {
          // 遊蕩：慢慢漂移，別飄出窩太遠
          m.timer -= dt;
          if (m.timer <= 0) {
            m.timer = 1.5 + Math.random() * 2.5;
            const a = Math.random() * Math.PI * 2;
            m.vel.x = Math.cos(a) * 0.9;
            m.vel.z = Math.sin(a) * 0.9;
          }
          const hx = m.nest.x - m.pos.x, hz = m.nest.z - m.pos.z;
          const hd = Math.hypot(hx, hz);
          if (hd > m.nest.r * 1.6) { m.vel.x += hx / hd * 1.2; m.vel.z += hz / hd * 1.2; }
          m.pos.x += m.vel.x * dt;
          m.pos.z += m.vel.z * dt;
        } else if (m.state === 1) {
          // 擊飛：摩擦減速，時間到回遊蕩
          m.timer -= dt;
          m.vel.multiplyScalar(Math.max(0, 1 - 4.5 * dt));
          m.vel.y -= 12 * dt;
          m.pos.addScaledVector(m.vel, dt);
          const gh = groundHeight(m.pos.x, m.pos.z) + 0.7;
          if (m.pos.y < gh) { m.pos.y = gh; m.vel.y = Math.abs(m.vel.y) * 0.4; }
          if (m.timer <= 0) m.state = 0;
        } else {
          // 消散：等重生
          m.timer -= dt;
          if (m.timer <= 0) {
            const a = Math.random() * Math.PI * 2;
            const d = Math.random() * m.nest.r;
            m.pos.set(m.nest.x + Math.cos(a) * d, 0, m.nest.z + Math.sin(a) * d);
            m.hp = HP; m.state = 0; m.flash = 1;
          }
        }
        if (m.flash > 0) {
          m.flash = Math.max(0, m.flash - dt * 3.2);
          c.copy(m.base).lerp(WHITE, m.flash);
          this.bodies.setColorAt(m.i, c);
          colorDirty = true;
        }
      }

      // 寫矩陣（消散的縮到 0 藏起來）
      const groundY = groundHeight(m.pos.x, m.pos.z);
      const hover = m.state === 1 ? m.pos.y : groundY + 0.9 + Math.sin(t * 2.2 + m.phase) * 0.22;
      const y = m.state === 1 ? hover : hover;
      if (m.state === 1) m.pos.y = y;
      const sc = m.state === 2 ? 0 : 1;
      e.set(0, Math.sin(t * 0.8 + m.phase) * 0.6, 0);
      q.setFromEuler(e);
      s.setScalar(sc);
      m4.compose(_v.set(m.pos.x, y, m.pos.z), q, s);
      this.bodies.setMatrixAt(m.i, m4);

      // 翅膀：快速撲動（縮放模擬），左右兩片
      const flap = Math.sin(t * 14 + m.phase) * 0.55;
      for (let w = 0; w < 2; w++) {
        const side = w ? 1 : -1;
        e.set(0, side * (0.7 + flap * 0.5), side * 0.5);
        q.setFromEuler(e);
        s.setScalar(sc);
        m4.compose(
          _v.set(m.pos.x + side * 0.26 * sc, y + 0.12 * sc, m.pos.z), q, s);
        this.wings.setMatrixAt(m.i * 2 + w, m4);
      }
    }

    this.bodies.instanceMatrix.needsUpdate = true;
    this.wings.instanceMatrix.needsUpdate = true;
    if (colorDirty) this.bodies.instanceColor.needsUpdate = true;
  }

  aliveNear(pos, r) {
    return countAlive(this.mobs, pos, r, DEAD);
  }
}

const WHITE = new THREE.Color(0xffffff);
const _v = new THREE.Vector3();
