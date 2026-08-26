// 花妖精 —— 太陽花田的守衛。
//
// 設定考據（Touhou Wiki）：太陽花田是風見幽香的地盤，花田裡住著一群
// 依附花而生的妖精。牠們比一般妖精護短：不是「看到人就飄過來玩」，
// 而是「有人踩進花田就成群圍上來趕人」。
//
// 跟妖怪兔（rabbits.js）的差別全在行為：兔子在地上跳著追，花妖精浮在
// 空中、繞著玩家盤旋伺機衝刺，被打飛後會慢慢飄回花上。命中判定與
// 傷害結算共用 mobcore.js。
//
// 渲染全走 InstancedMesh：身體（發光的小球）、翅膀（每隻兩片）各一個。

import * as THREE from 'three';
import { groundHeight } from '../world/terrain.js';
import { sectorHits, countAlive } from './mobcore.js';

const MOB_R = 0.55;
const RESPAWN = 16;
const HP = 85;            // 比妖怪兔（60）硬 —— 花田是第二期最後一站
const SIGHT = 19;
const LOSE = 30;
const REACH = 2.0;
const ORBIT_R = 4.2;      // 盤旋半徑
const ORBIT_SPEED = 2.6;
const DASH_SPEED = 8.5;   // 衝刺很快，但只衝一小段
const FLY_H = 1.7;        // 離地高度

// 花的顏色 —— 每隻妖精對應一種花
const HUES = [0xf2c832, 0xf0a03c, 0xe8e0a0, 0xf4d86a, 0xe0b848];

/** 狀態：盤旋 / 衝刺 / 被打飛 / 消散 */
const ORBIT = 0, DASH = 1, KNOCKED = 2, GONE = 3;

export class FlowerFairies {
  /**
   * @param {THREE.Scene|THREE.Object3D} scene
   * @param {{x:number,z:number,r:number}[]} patches 花叢（絕對座標 + 半徑）
   * @param {number} [perPatch=6] 每叢幾隻
   * @param {object} [hooks]
   * @param {(dmg:number, mob:object)=>void} [hooks.onAttack] 撞到玩家時呼叫
   * @param {number} [hooks.damage=9]
   */
  constructor(scene, patches, perPatch = 6, hooks = {}) {
    this.scene = scene;
    this.hooks = hooks;
    this.attackDamage = hooks.damage ?? 9;
    const total = patches.length * perPatch;

    // 身體：自己會發光的小球（跟神社的妖精同一種處理 —— 不吃場景光，
    // 夜裡才會像一點漂浮的燈火而不是一坨黑影）
    const bodyGeo = new THREE.SphereGeometry(0.26, 10, 8);
    const bodyMat = new THREE.MeshBasicMaterial({ color: 0xffffff });
    this.bodies = new THREE.InstancedMesh(bodyGeo, bodyMat, total);
    this.bodies.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(total * 3), 3);
    this.bodies.frustumCulled = false;

    // 翅膀：兩片半透明的花瓣狀面片
    const wingGeo = new THREE.CircleGeometry(0.34, 7, 0, Math.PI);
    const wingMat = new THREE.MeshBasicMaterial({
      color: 0xffffff, transparent: true, opacity: 0.45, side: THREE.DoubleSide, depthWrite: false,
    });
    this.wings = new THREE.InstancedMesh(wingGeo, wingMat, total * 2);
    this.wings.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(total * 2 * 3), 3);
    this.wings.frustumCulled = false;

    scene.add(this.bodies, this.wings);

    this.mobs = [];
    const col = new THREE.Color();
    let k = 0;
    for (const patch of patches) {
      for (let i = 0; i < perPatch; i++) {
        const a = Math.random() * Math.PI * 2;
        const d = Math.random() * patch.r;
        const x = patch.x + Math.cos(a) * d, z = patch.z + Math.sin(a) * d;
        col.setHex(HUES[(Math.random() * HUES.length) | 0]);
        this.bodies.setColorAt(k, col);
        this.wings.setColorAt(k * 2, col);
        this.wings.setColorAt(k * 2 + 1, col);
        this.mobs.push({
          i: k,
          home: { x: patch.x, z: patch.z, r: patch.r },
          pos: new THREE.Vector3(x, 0, z),
          vel: new THREE.Vector3(),
          hp: HP, state: ORBIT,
          timer: Math.random() * 3,
          phase: Math.random() * Math.PI * 2,      // 盤旋相位
          bob: Math.random() * Math.PI * 2,        // 上下浮動相位
          yaw: Math.random() * Math.PI * 2,
          cooldown: 0,
          flash: 0,
          base: col.clone(),
        });
        k++;
      }
    }
    this.bodies.instanceColor.needsUpdate = true;
    this.wings.instanceColor.needsUpdate = true;

    this._m = new THREE.Matrix4();
    this._q = new THREE.Quaternion();
    this._s = new THREE.Vector3(1, 1, 1);
    this._e = new THREE.Euler();
    this._c = new THREE.Color();
    this.kills = 0;
  }

  inSector(origin, yaw, range, arc) {
    return sectorHits(this.mobs, origin, yaw, range, arc, MOB_R, GONE);
  }

  aliveNear(pos, r) {
    return countAlive(this.mobs, pos, r, GONE);
  }

  /** 造成傷害 + 擊飛。回傳是否擊殺。 */
  damage(m, dmg, dirX, dirZ) {
    m.hp -= dmg;
    m.flash = 1;
    const killed = m.hp <= 0;
    const k = killed ? 12 : 8;
    m.vel.set(dirX * k, killed ? 8 : 5, dirZ * k);
    if (killed) {
      m.state = GONE;
      m.timer = RESPAWN;
      this.kills++;
      return true;
    }
    m.state = KNOCKED;
    m.timer = 0.55;
    return false;
  }

  update(dt, t, playerPos) {
    const m4 = this._m, q = this._q, s = this._s, e = this._e, c = this._c;
    let colorDirty = false;

    for (const m of this.mobs) {
      const far = playerPos && Math.hypot(m.pos.x - playerPos.x, m.pos.z - playerPos.z) > 100;

      if (!far) {
        if (m.cooldown > 0) m.cooldown -= dt;
        m.bob += dt * 2.4;
        const pd = playerPos
          ? Math.hypot(m.pos.x - playerPos.x, m.pos.z - playerPos.z)
          : Infinity;

        if (m.state === ORBIT) {
          if (pd < SIGHT && playerPos) {
            // 發現玩家：繞著他盤旋，冷卻好了就衝一下。
            // 「繞圈再衝」而不是直線追 —— 空中的敵人直線衝過來會很像撞球，
            // 盤旋讓玩家有時間看清楚牠們從哪邊來。
            m.phase += dt * ORBIT_SPEED;
            const tx = playerPos.x + Math.cos(m.phase) * ORBIT_R;
            const tz = playerPos.z + Math.sin(m.phase) * ORBIT_R;
            const dx = tx - m.pos.x, dz = tz - m.pos.z;
            const dd = Math.hypot(dx, dz) || 1;
            const sp = 4.2;
            m.pos.x += (dx / dd) * sp * dt;
            m.pos.z += (dz / dd) * sp * dt;
            m.yaw = Math.atan2(playerPos.x - m.pos.x, playerPos.z - m.pos.z);
            if (m.cooldown <= 0 && pd < ORBIT_R * 2.2) {
              m.state = DASH;
              m.timer = 0.55;
              m.cooldown = 2.4;
            }
          } else {
            // 沒人：在自己的花叢上方慢慢飄
            m.timer -= dt;
            if (m.timer <= 0) {
              m.timer = 1.6 + Math.random() * 2.6;
              m.yaw = Math.random() * Math.PI * 2;
            }
            const hx = m.home.x - m.pos.x, hz = m.home.z - m.pos.z;
            if (Math.hypot(hx, hz) > m.home.r) m.yaw = Math.atan2(hx, hz);
            m.pos.x += Math.sin(m.yaw) * 1.3 * dt;
            m.pos.z += Math.cos(m.yaw) * 1.3 * dt;
          }

        } else if (m.state === DASH) {
          // 衝刺：朝玩家直線撞過去，撞到或時間到就回盤旋
          m.timer -= dt;
          if (!playerPos || m.timer <= 0 || pd > LOSE) {
            m.state = ORBIT;
          } else {
            const dx = playerPos.x - m.pos.x, dz = playerPos.z - m.pos.z;
            const dd = Math.hypot(dx, dz) || 1;
            m.pos.x += (dx / dd) * DASH_SPEED * dt;
            m.pos.z += (dz / dd) * DASH_SPEED * dt;
            m.yaw = Math.atan2(dx, dz);
            if (pd < REACH) {
              m.state = ORBIT;
              this.hooks.onAttack?.(this.attackDamage, m);
            }
          }

        } else if (m.state === KNOCKED) {
          m.timer -= dt;
          m.vel.multiplyScalar(Math.max(0, 1 - 3.6 * dt));
          m.vel.y -= 16 * dt;
          m.pos.addScaledVector(m.vel, dt);
          const gh = groundHeight(m.pos.x, m.pos.z) + 0.5;
          if (m.pos.y < gh) { m.pos.y = gh; m.vel.y = Math.abs(m.vel.y) * 0.3; }
          if (m.timer <= 0) { m.state = ORBIT; m.cooldown = 0.9; }

        } else {
          m.timer -= dt;
          if (m.timer <= 0) {
            const a = Math.random() * Math.PI * 2;
            const d = Math.random() * m.home.r;
            m.pos.set(m.home.x + Math.cos(a) * d, 0, m.home.z + Math.sin(a) * d);
            m.hp = HP; m.state = ORBIT; m.flash = 1; m.cooldown = 0;
          }
        }

        if (m.flash > 0) {
          m.flash = Math.max(0, m.flash - dt * 3.2);
          c.copy(m.base).lerp(WHITE, m.flash);
          this.bodies.setColorAt(m.i, c);
          this.wings.setColorAt(m.i * 2, c);
          this.wings.setColorAt(m.i * 2 + 1, c);
          colorDirty = true;
        }
      }

      // ---- 寫矩陣 ----
      const gone = m.state === GONE;
      const sc = gone ? 0 : 1;
      const groundY = groundHeight(m.pos.x, m.pos.z);
      const y = m.state === KNOCKED
        ? m.pos.y
        : groundY + FLY_H + Math.sin(m.bob) * 0.22;
      if (m.state !== KNOCKED) m.pos.y = y;

      e.set(0, m.yaw, 0);
      q.setFromEuler(e);
      s.setScalar(sc);
      m4.compose(_v.set(m.pos.x, y, m.pos.z), q, s);
      this.bodies.setMatrixAt(m.i, m4);

      // 翅膀：左右各一片，拍動用快速的擺角（衝刺時拍得更快）
      const beat = Math.sin(t * (m.state === DASH ? 30 : 18) + m.phase) * 0.5;
      for (let w = 0; w < 2; w++) {
        const side = w ? 1 : -1;
        e.set(0, m.yaw + side * (0.9 + beat * side), 0);
        q.setFromEuler(e);
        s.setScalar(sc);
        _v.set(
          m.pos.x - Math.sin(m.yaw) * 0.08,
          y + 0.06,
          m.pos.z - Math.cos(m.yaw) * 0.08
        );
        m4.compose(_v, q, s);
        this.wings.setMatrixAt(m.i * 2 + w, m4);
      }
    }

    this.bodies.instanceMatrix.needsUpdate = true;
    this.wings.instanceMatrix.needsUpdate = true;
    if (colorDirty) {
      this.bodies.instanceColor.needsUpdate = true;
      this.wings.instanceColor.needsUpdate = true;
    }
  }
}

const WHITE = new THREE.Color(0xffffff);
const _v = new THREE.Vector3();
