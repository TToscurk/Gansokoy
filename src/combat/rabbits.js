// 妖怪兔 —— 迷途竹林的原住民。
//
// 設定考據（Touhou Wiki）：迷いの竹林住著大量妖怪兔，是因幡てゐ的手下、
// 也是永遠亭的下人。牠們不像妖精那樣無害好玩 —— 會成群圍上來，
// 是這個專案第一種「會主動找玩家麻煩」的怪。
//
// 跟妖精（mobs.js）的差別全在行為：妖精在窩附近飄，兔子會發現玩家、
// 跳著追過來、貼身時撲一下。命中判定與傷害結算共用 mobcore.js。
//
// 渲染一樣全部走 InstancedMesh：身體、耳朵（每隻兩片）各一個，
// 五十隻同屏也只有兩個 draw call。

import * as THREE from 'three';
import { groundHeight } from '../world/terrain.js';
import { sectorHits, countAlive } from './mobcore.js';

const MOB_R = 0.5;        // 命中判定半徑
const RESPAWN = 14;       // 重生秒數
const HP = 60;            // 比妖精（40）硬一點
const SIGHT = 15;         // 發現玩家的距離
const LOSE = 24;          // 超過這個距離放棄追擊
const REACH = 1.5;        // 撲擊的距離
const SPEED = 3.4;        // 追擊速度（玩家走路 5.4、衝刺更快，追不上是故意的）

// 白、灰、茶、淡褐 —— 竹林裡的野兔配色
const FUR = [0xf0ece4, 0xcfc6b8, 0xa89078, 0x8a7460, 0xe0d4c0];

/** 三段狀態 */
const WANDER = 0, CHASE = 1, KNOCKED = 2, GONE = 3;

export class RabbitMobs {
  /**
   * @param {THREE.Scene|THREE.Object3D} scene
   * @param {{x:number,z:number,r:number}[]} nests 巢穴（絕對座標 + 半徑）
   * @param {number} [perNest=6] 每窩幾隻
   * @param {object} [hooks]
   * @param {(dmg:number, mob:object)=>void} [hooks.onAttack] 撲中玩家時呼叫
   * @param {number} [hooks.damage=7] 一次撲擊的傷害
   */
  constructor(scene, nests, perNest = 6, hooks = {}) {
    this.scene = scene;
    this.hooks = hooks;
    this.attackDamage = hooks.damage ?? 7;
    const total = nests.length * perNest;

    // 身體：橢圓的一坨。兔子是實體生物，用吃光的 StandardMaterial
    // （妖精是自己會發光的小東西才用 BasicMaterial）。
    // 身體要小一點、耳朵要長一點 —— 不然遠看只是一顆蛋。
    // 兔子的辨識度幾乎全靠剪影上那兩隻耳朵。
    const bodyGeo = new THREE.SphereGeometry(0.25, 10, 8);
    bodyGeo.scale(1, 0.8, 1.3);
    const bodyMat = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.92 });
    this.bodies = new THREE.InstancedMesh(bodyGeo, bodyMat, total);
    this.bodies.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(total * 3), 3);
    this.bodies.castShadow = true;
    this.bodies.frustumCulled = false;

    // 耳朵：細長的膠囊，每隻兩片
    const earGeo = new THREE.CapsuleGeometry(0.045, 0.46, 3, 6);
    this.ears = new THREE.InstancedMesh(earGeo, bodyMat, total * 2);
    this.ears.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(total * 2 * 3), 3);
    this.ears.castShadow = true;
    this.ears.frustumCulled = false;

    scene.add(this.bodies, this.ears);

    this.mobs = [];
    const col = new THREE.Color();
    let k = 0;
    for (const nest of nests) {
      for (let i = 0; i < perNest; i++) {
        const a = Math.random() * Math.PI * 2;
        const d = Math.random() * nest.r;
        const x = nest.x + Math.cos(a) * d, z = nest.z + Math.sin(a) * d;
        col.setHex(FUR[(Math.random() * FUR.length) | 0]);
        this.bodies.setColorAt(k, col);
        this.ears.setColorAt(k * 2, col);
        this.ears.setColorAt(k * 2 + 1, col);
        this.mobs.push({
          i: k,
          nest: { x: nest.x, z: nest.z, r: nest.r },
          pos: new THREE.Vector3(x, 0, z),
          vel: new THREE.Vector3(),
          hp: HP, state: WANDER,
          timer: Math.random() * 3,
          hop: Math.random() * Math.PI * 2,   // 跳躍相位
          yaw: Math.random() * Math.PI * 2,
          cooldown: 0,                        // 撲擊冷卻
          flash: 0,
          base: col.clone(),
        });
        k++;
      }
    }
    this.bodies.instanceColor.needsUpdate = true;
    this.ears.instanceColor.needsUpdate = true;

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
    const k = killed ? 11 : 7.5;
    m.vel.set(dirX * k, killed ? 7 : 4.5, dirZ * k);
    if (killed) {
      m.state = GONE;
      m.timer = RESPAWN;
      this.kills++;
      return true;
    }
    m.state = KNOCKED;
    m.timer = 0.5;
    return false;
  }

  update(dt, t, playerPos) {
    const m4 = this._m, q = this._q, s = this._s, e = this._e, c = this._c;
    let colorDirty = false;

    for (const m of this.mobs) {
      // 玩家在很遠的另一頭時，行為完全不用算（矩陣還是要寫，不然會留在原地閃）
      const far = playerPos && Math.hypot(m.pos.x - playerPos.x, m.pos.z - playerPos.z) > 90;

      if (!far) {
        if (m.cooldown > 0) m.cooldown -= dt;
        const pd = playerPos
          ? Math.hypot(m.pos.x - playerPos.x, m.pos.z - playerPos.z)
          : Infinity;

        if (m.state === WANDER) {
          // 遊蕩：不時換個方向跳兩下，別離巢太遠
          m.timer -= dt;
          if (m.timer <= 0) {
            m.timer = 1.2 + Math.random() * 2.4;
            m.yaw = Math.random() * Math.PI * 2;
          }
          const hx = m.nest.x - m.pos.x, hz = m.nest.z - m.pos.z;
          const hd = Math.hypot(hx, hz);
          if (hd > m.nest.r * 1.5) m.yaw = Math.atan2(hx, hz);
          const sp = 1.1;
          m.pos.x += Math.sin(m.yaw) * sp * dt;
          m.pos.z += Math.cos(m.yaw) * sp * dt;
          m.hop += dt * 5.5;

          if (pd < SIGHT) m.state = CHASE;

        } else if (m.state === CHASE) {
          // 追擊：朝玩家跳過去，貼身就撲一下
          if (pd > LOSE || !playerPos) {
            m.state = WANDER;
            m.timer = 1;
          } else {
            m.yaw = Math.atan2(playerPos.x - m.pos.x, playerPos.z - m.pos.z);
            if (pd > REACH) {
              m.pos.x += Math.sin(m.yaw) * SPEED * dt;
              m.pos.z += Math.cos(m.yaw) * SPEED * dt;
              m.hop += dt * 9;
            } else if (m.cooldown <= 0) {
              // 撲擊。撲完有 1.6 秒冷卻，一群兔子才不會黏在臉上連續撲
              m.cooldown = 1.6;
              m.hop = Math.PI * 0.5;      // 跳到最高點，看起來像撲上來
              this.hooks.onAttack?.(this.attackDamage, m);
            }
          }

        } else if (m.state === KNOCKED) {
          // 擊飛：拋物線 + 摩擦，落地後回遊蕩
          m.timer -= dt;
          m.vel.multiplyScalar(Math.max(0, 1 - 4.2 * dt));
          m.vel.y -= 22 * dt;
          m.pos.addScaledVector(m.vel, dt);
          const gh = groundHeight(m.pos.x, m.pos.z) + 0.3;
          if (m.pos.y < gh) { m.pos.y = gh; m.vel.y = Math.abs(m.vel.y) * 0.35; }
          if (m.timer <= 0) { m.state = CHASE; m.cooldown = 0.6; }

        } else {
          // 消散：等重生。兔子不是「打不死的妖精」，牠們是逃走了又跑回來
          m.timer -= dt;
          if (m.timer <= 0) {
            const a = Math.random() * Math.PI * 2;
            const d = Math.random() * m.nest.r;
            m.pos.set(m.nest.x + Math.cos(a) * d, 0, m.nest.z + Math.sin(a) * d);
            m.hp = HP; m.state = WANDER; m.flash = 1; m.cooldown = 0;
          }
        }

        if (m.flash > 0) {
          m.flash = Math.max(0, m.flash - dt * 3.2);
          c.copy(m.base).lerp(WHITE, m.flash);
          this.bodies.setColorAt(m.i, c);
          this.ears.setColorAt(m.i * 2, c);
          this.ears.setColorAt(m.i * 2 + 1, c);
          colorDirty = true;
        }
      }

      // ---- 寫矩陣 ----
      const gone = m.state === GONE;
      const sc = gone ? 0 : 1;
      const groundY = groundHeight(m.pos.x, m.pos.z);
      // 跳躍：|sin| 的弧線，落地那一刻速度最快 —— 兔子的招牌動作
      const hopH = m.state === KNOCKED ? 0 : Math.abs(Math.sin(m.hop)) * 0.34;
      const y = m.state === KNOCKED ? m.pos.y : groundY + 0.3 + hopH;
      if (m.state !== KNOCKED) m.pos.y = y;

      // 跳到高處時身體前傾，落地時壓扁一點
      const lean = m.state === KNOCKED ? 0 : hopH * 0.9;
      e.set(-lean, m.yaw, 0);
      q.setFromEuler(e);
      s.setScalar(sc);
      m4.compose(_v.set(m.pos.x, y, m.pos.z), q, s);
      this.bodies.setMatrixAt(m.i, m4);

      // 耳朵：跳起來時往後倒，落地時立起來
      for (let w = 0; w < 2; w++) {
        const side = w ? 1 : -1;
        const ex = -0.22 - lean * 1.2;   // 立得直一點，剪影才讀得出是耳朵
        e.set(ex, m.yaw, side * 0.22);
        q.setFromEuler(e);
        s.setScalar(sc);
        // 耳朵長在頭上、略偏後
        const hx = Math.sin(m.yaw), hz = Math.cos(m.yaw);
        _v.set(
          m.pos.x + hx * 0.1 + Math.cos(m.yaw) * side * 0.09,
          y + 0.34,
          m.pos.z + hz * 0.1 - Math.sin(m.yaw) * side * 0.09
        );
        m4.compose(_v, q, s);
        this.ears.setMatrixAt(m.i * 2 + w, m4);
      }
    }

    this.bodies.instanceMatrix.needsUpdate = true;
    this.ears.instanceMatrix.needsUpdate = true;
    if (colorDirty) {
      this.bodies.instanceColor.needsUpdate = true;
      this.ears.instanceColor.needsUpdate = true;
    }
  }
}

const WHITE = new THREE.Color(0xffffff);
const _v = new THREE.Vector3();
