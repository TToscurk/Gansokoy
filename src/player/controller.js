import * as THREE from 'three';
import { groundHeight, terrainNormal } from '../world/terrain.js';
import { WORLD } from '../config.js';
import { animateCharacter } from '../entities/model.js';

const PLAYER_R = 0.42;
const EYE = 1.55;

export class PlayerController {
  constructor(model, camera, domElement, colliders) {
    this.model = model;
    this.camera = camera;
    this.dom = domElement;
    this.colliders = colliders;

    this.pos = new THREE.Vector3(0, 0, 0);
    this.vel = new THREE.Vector3();
    this.yaw = 0;                 // 角色朝向
    this.grounded = false;
    this.flying = false;
    this.speedMul = 1;

    /** 地圖邊界（空氣牆）：{ hx, hz } 局部座標的半邊長，null = 不設限。
     *  由 main.js 在載圖時依 meta.size 設定。 */
    this.bounds = null;

    // 相機軌道
    this.camYaw = 0;
    this.camPitch = 0.24;
    this.camDist = 5.2;
    this.camDistTarget = 5.2;
    this._camPos = new THREE.Vector3();
    this._camLook = new THREE.Vector3();

    this.keys = Object.create(null);
    this.pressed = Object.create(null);   // 只在按下那一幀為 true
    // 從目前的實際狀態起算，不要一律 false。換角色會換一個新的 controller，
    // 這時滑鼠通常還鎖著 —— pointerlockchange 不會再觸發一次，
    // 起始值寫死 false 的話新 controller 會永遠以為沒鎖，鍵盤全部失效。
    this.locked = document.pointerLockElement === domElement;
    this.enabled = true;

    // 滑鼠
    this.sensitivity = 1.0;
    this.invertY = false;

    // 角色能力。跳躍/衝刺是初速與倍率，實際高度 = v²/(2·|gravity|)，
    // 目前 gravity = -26，所以 9.2 大約是 1.6m。
    this.canFly = true;
    this.maxAirJumps = 0;
    this.airJumpsUsed = 0;
    this.jumpV = 9.2;
    this.airJumpV = 8.4;
    this.sprintMul = 1.85;
    // 坡度阻擋：地面每公尺水平位移最多能升多少（1.0 ≈ 45°）。
    // null = 不限制（神社的階梯高度場是瞬間跳變，套這個會把樓梯當牆）。
    // 谷道類地圖（獸道、竹林）設 ~1.05，玩家就爬不上邊坡的山稜。
    this.maxGrade = null;

    this._listeners = [];
    this._bind();
  }

  /**
   * 所有 DOM 監聽器都記在 _listeners 裡，dispose() 才拆得乾淨。
   * 換角色會丟掉舊的 controller 換一個新的 —— 沒有 dispose 的話舊的會繼續
   * 收鍵盤／滑鼠／滾輪事件，兩個 controller 搶同一組輸入。
   */
  _bind() {
    const on = (target, type, fn, opts) => {
      target.addEventListener(type, fn, opts);
      this._listeners.push([target, type, fn, opts]);
    };

    on(window, 'keydown', e => {
      if (e.repeat) return;
      this.keys[e.code] = true;
      this.pressed[e.code] = true;
      if (e.code === 'KeyF' && this.enabled) this.toggleFlight();
      // 避免空白鍵捲動頁面
      if (e.code === 'Space') e.preventDefault();
    });
    on(window, 'keyup', e => { this.keys[e.code] = false; });

    on(this.dom, 'click', () => {
      if (!this.locked && this.enabled) this.dom.requestPointerLock();
    });

    on(document, 'pointerlockchange', () => {
      this.locked = document.pointerLockElement === this.dom;
    });

    on(document, 'mousemove', e => {
      if (!this.locked) return;
      // camPitch 變大 = 相機升高 = 視線往下。
      // 所以滑鼠往下（movementY > 0）應該讓 camPitch 變大才是順向；
      // 原本寫成 -= ，等於 Y 軸整個相反。
      this.camYaw -= e.movementX * 0.0022 * this.sensitivity;
      const dy = e.movementY * 0.0019 * this.sensitivity;
      this.camPitch += this.invertY ? -dy : dy;
      this.camPitch = Math.max(-0.9, Math.min(1.15, this.camPitch));
    });

    on(this.dom, 'wheel', e => {
      this.camDistTarget = Math.max(1.6, Math.min(14, this.camDistTarget + e.deltaY * 0.006));
      e.preventDefault();
    }, { passive: false });
  }

  /** 換角色／關場景時務必呼叫，否則舊 controller 會繼續吃輸入 */
  dispose() {
    for (const [target, type, fn, opts] of this._listeners) {
      target.removeEventListener(type, fn, opts);
    }
    this._listeners.length = 0;
    this.enabled = false;
  }

  toggleFlight() {
    if (!this.canFly) return;          // 人類劍士不會飛
    if (this.flying) { this._endFlight(); return; }
    this.flying = true;
    this.vel.y = Math.max(this.vel.y, 2.5);
  }

  /** 結束飛行。
   *  飛行速度是步行的三倍，若直接切回地面模式會帶著這股慣性滑出去，
   *  方向感整個亂掉。這裡把水平速度收斂回步行區間。 */
  _endFlight() {
    this.flying = false;
    const s = Math.hypot(this.vel.x, this.vel.z);
    const cap = 6.5 * this.speedMul;
    if (s > cap) {
      const k = cap / s;
      this.vel.x *= k;
      this.vel.z *= k;
    }
    this.airJumpsUsed = this.maxAirJumps;   // 落地前不給額外空中跳
  }

  // y 可選：室內傳送這類落點不在地形上的情況直接給定高度；
  // 沒給就照舊貼地形（舊呼叫端零影響）。
  teleport(x, z, y) {
    this.pos.set(x, y !== undefined ? y : groundHeight(x, z) + 0.2, z);
    this.vel.set(0, 0, 0);
  }

  /** 水平推開，避免走進建築 */
  /**
   * 空氣牆 —— 把玩家夾在現行地圖的範圍內。
   *
   * 分圖之後每張圖只有 400～600 公尺，而 groundHeight() 在圖外一樣有值
   * （它是世界高度場），所以不夾的話玩家可以一直走出去，站在沒有貼圖的
   * 遠景裙襬上（看起來就是一片白色地板），走到 1100 公尺外連裙襬都沒了。
   *
   * 夾座標而不是擺四道碰撞盒：一個地方改，18 張圖自動生效，
   * 轉角也不會有漏洞。飛行同樣受限（飛出去問題一樣）。
   *
   * 牆的位置是圖邊往內 1 公尺。實測 36 個出入口的觸發圓心全都在牆內，
   * 所以不會有「被牆擋住而搆不到出入口」的情況 —— 玩家只要進到
   * 圓心 r 公尺內就會觸發，不必走到圓的外緣。
   */
  _clampToBounds() {
    const b = this.bounds;
    if (!b) return;
    const hx = b.hx - 1, hz = b.hz - 1;
    if (this.pos.x > hx)  { this.pos.x = hx;  if (this.vel.x > 0) this.vel.x = 0; }
    if (this.pos.x < -hx) { this.pos.x = -hx; if (this.vel.x < 0) this.vel.x = 0; }
    if (this.pos.z > hz)  { this.pos.z = hz;  if (this.vel.z > 0) this.vel.z = 0; }
    if (this.pos.z < -hz) { this.pos.z = -hz; if (this.vel.z < 0) this.vel.z = 0; }
  }

  /**
   * 撞到東西之後，把「往牆裡」的那份速度吃掉，只留下沿著牆面滑動的分量。
   *
   * 不做這件事的話：位置每幀被推回表面，速度卻還指著牆內，下一幀又擠進去、
   * 又被推出來 —— 那正是「碰到物件角色會移位／抖動」的成因。清掉法線方向的
   * 速度後，貼著樹或牆走就只是單純地被擋住，手感是實心的。
   * @param {number} nx @param {number} nz 單位法線（由物體指向玩家）
   */
  _killInward(nx, nz) {
    const into = this.vel.x * nx + this.vel.z * nz;
    if (into < 0) { this.vel.x -= into * nx; this.vel.z -= into * nz; }
  }

  _resolveCollisions() {
    const p = this.pos;
    for (const c of this.colliders) {
      // 垂直範圍檢查
      if (p.y + 1.7 < c.y || p.y > c.y + c.h) continue;
      // 可行走平台：高度足以踏上頂面時不做水平阻擋（台階 / 高床地板用）
      if (c.walk && p.y >= c.y + c.h - 0.55) continue;

      if (c.r !== undefined) {
        // 圓柱
        const dx = p.x - c.x, dz = p.z - c.z;
        const d = Math.hypot(dx, dz);
        const min = c.r + PLAYER_R;
        if (d < min && d > 1e-5) {
          const k = (min - d) / d;
          p.x += dx * k;
          p.z += dz * k;
          this._killInward(dx / d, dz / d);
        }
      } else {
        // 方盒（可帶 Y 軸旋轉）
        const rot = c.rotY || 0;
        const cs = Math.cos(-rot), sn = Math.sin(-rot);
        let dx = p.x - c.x, dz = p.z - c.z;
        const lx = dx * cs - dz * sn;
        const lz = dx * sn + dz * cs;
        const ex = c.hw + PLAYER_R, ez = c.hd + PLAYER_R;
        if (Math.abs(lx) < ex && Math.abs(lz) < ez) {
          // 推向最近的面
          const px = ex - Math.abs(lx);
          const pz = ez - Math.abs(lz);
          let nlx = lx, nlz = lz;
          let nx = 0, nz = 0;                       // 被推開的方向（世界座標法線）
          if (px < pz) { nlx = Math.sign(lx || 1) * ex; nx = Math.sign(lx || 1); }
          else { nlz = Math.sign(lz || 1) * ez; nz = Math.sign(lz || 1); }
          const cs2 = Math.cos(rot), sn2 = Math.sin(rot);
          p.x = c.x + (nlx * cs2 - nlz * sn2);
          p.z = c.z + (nlx * sn2 + nlz * cs2);
          this._killInward(nx * cs2 - nz * sn2, nx * sn2 + nz * cs2);
        }
      }
    }

    // 世界邊界
    const lim = WORLD.size * 0.47;
    p.x = Math.max(-lim, Math.min(lim, p.x));
    p.z = Math.max(-lim, Math.min(lim, p.z));
  }

  update(dt, t) {
    if (!this.enabled) {
      this._updateCamera(dt);
      animateCharacter(this.model, t, 0);
      // 對話期間也要清掉，否則累積的按鍵會在對話結束的瞬間一次生效
      this.pressed = Object.create(null);
      return;
    }

    const k = this.keys;
    const sprint = k['ShiftLeft'] || k['ShiftRight'];

    // --- 輸入向量（相對相機） ---
    let ix = 0, iz = 0;
    if (k['KeyW'] || k['ArrowUp']) iz -= 1;
    if (k['KeyS'] || k['ArrowDown']) iz += 1;
    if (k['KeyA'] || k['ArrowLeft']) ix -= 1;
    if (k['KeyD'] || k['ArrowRight']) ix += 1;

    const mag = Math.hypot(ix, iz);
    let wishX = 0, wishZ = 0;
    if (mag > 0) {
      ix /= mag; iz /= mag;
      // camYaw 定義的是「相機相對角色的方位」，所以水平前方是 -dir，不是 +dir。
      // 少了這組負號的話，camYaw = 0 時剛好正確，但一轉動視角 WASD 就會相對
      // 視線鏡像 —— 轉到 90 度時 W 會直接往後走。
      const cs = Math.cos(this.camYaw), sn = Math.sin(this.camYaw);
      const fx = -sn, fz = -cs;      // 前
      const rx = cs, rz = -sn;       // 右 = cross(前, 上)
      wishX = ix * rx - iz * fx;
      wishZ = ix * rz - iz * fz;
    }

    const base = this.flying ? 15 : 5.4;
    const speed = base * (sprint && !this.flying ? this.sprintMul
                        : sprint ? 1.85 : 1) * this.speedMul;

    // --- 水平運動 ---
    const accel = this.grounded || this.flying ? 16 : 6;
    this.vel.x += (wishX * speed - this.vel.x) * Math.min(1, accel * dt);
    this.vel.z += (wishZ * speed - this.vel.z) * Math.min(1, accel * dt);

    // --- 垂直運動 ---
    if (this.flying) {
      let vy = 0;
      if (k['Space']) vy += 1;
      if (k['ControlLeft'] || k['KeyC']) vy -= 1;
      const climb = 11 * (sprint ? 1.7 : 1);
      this.vel.y += (vy * climb - this.vel.y) * Math.min(1, 10 * dt);
    } else {
      this.vel.y += WORLD.gravity * dt;
      // 邊緣觸發，否則按住空白鍵會一次把空中跳全部用掉
      if (this.pressed['Space']) {
        if (this.grounded) {
          this.vel.y = this.jumpV;
          this.grounded = false;
          this.airJumpsUsed = 0;
        } else if (this.airJumpsUsed < this.maxAirJumps) {
          this.vel.y = this.airJumpV;
          this.airJumpsUsed++;
        }
      }
    }

    // --- 積分 ---
    const prevX = this.pos.x, prevZ = this.pos.z;
    this.pos.addScaledVector(this.vel, dt);

    // --- 坡度阻擋 ---
    // 往移動方向探 1.1 公尺，坡度超過 maxGrade 就把那個軸的位移取消
    // （分軸滑行：斜著撞山會貼著山腳滑，不是整個人定住）。
    // 用「探一段距離」而不是「這一幀的高差」——每幀高差在緩坡上永遠很小，
    // 擋不住持續爬坡；探 1.1m 才量得到真正的坡度。
    if (this.maxGrade != null && !this.flying) {
      const PROBE = 1.1;
      const g0 = groundHeight(prevX, prevZ);
      const steep = (dx, dz) => {
        const d = Math.hypot(dx, dz);
        if (d < 1e-6) return false;
        const px = prevX + (dx / d) * PROBE, pz = prevZ + (dz / d) * PROBE;
        return (groundHeight(px, pz) - g0) / PROBE > this.maxGrade;
      };
      const mx = this.pos.x - prevX, mz = this.pos.z - prevZ;
      if (steep(mx, mz)) {
        if (!steep(mx, 0)) { this.pos.z = prevZ; this.vel.z = 0; }
        else if (!steep(0, mz)) { this.pos.x = prevX; this.vel.x = 0; }
        else { this.pos.x = prevX; this.pos.z = prevZ; this.vel.x = this.vel.z = 0; }
      }
    }

    this._clampToBounds();
    this._resolveCollisions();

    // --- 地面 ---
    const gh = groundHeight(this.pos.x, this.pos.z);
    let floor = Math.max(gh, WORLD.waterLevel - 0.6);
    // 可行走平台（walk 碰撞盒）：站在頂面附近時，地面吸附到平台頂。
    // 0.55 的步高容許讓台階可以一級一級走上去；低於頂面太多則視為在平台下方。
    for (const c of this.colliders) {
      if (!c.walk) continue;
      if (c.hw == null) continue;    // 圓柱沒有頂面吸附 —— walk 只支援方盒
      // 邊緣多留 0.28m 寬容：站在平台邊緣時，腳的圓半徑有一部分懸空，
      // 沒有寬容的話會在「吸附到頂/掉下去」之間來回抖動。
      if (Math.abs(this.pos.x - c.x) > c.hw + 0.28 || Math.abs(this.pos.z - c.z) > c.hd + 0.28) continue;
      const top = c.y + c.h;
      if (top > floor && this.pos.y >= top - 0.55) floor = top;
    }

    if (this.flying) {
      // 飛行時不落地，但不能穿進地面
      if (this.pos.y < floor + 0.5) {
        this.pos.y = floor + 0.5;
        this.vel.y = Math.max(0, this.vel.y);
      }
      this.grounded = false;
      // 貼近地面時自動落地
      if (this.pos.y < floor + 0.6 && !k['Space'] && this.vel.y <= 0) {
        this._endFlight();
      }
    } else {
      if (this.pos.y <= floor) {
        this.pos.y = floor;
        this.vel.y = 0;
        if (!this.grounded) this.airJumpsUsed = 0;   // 著地後重置空中跳
        this.grounded = true;
      } else {
        this.grounded = false;
      }
    }

    // --- 模型朝向 ---
    const hSpeed = Math.hypot(this.vel.x, this.vel.z);
    if (hSpeed > 0.35) {
      const target = Math.atan2(this.vel.x, this.vel.z);
      let d = target - this.yaw;
      while (d > Math.PI) d -= Math.PI * 2;
      while (d < -Math.PI) d += Math.PI * 2;
      this.yaw += d * Math.min(1, 12 * dt);
    }

    this.model.position.copy(this.pos);
    this.model.rotation.y = this.yaw;

    // 飛行時身體前傾
    const rig = this.model.userData.rig;
    if (rig) {
      rig.float = this.flying;
      const tilt = this.flying ? Math.min(0.42, hSpeed * 0.028) : 0;
      this.model.rotation.x += (tilt - this.model.rotation.x) * Math.min(1, 6 * dt);
    }
    animateCharacter(this.model, t, hSpeed);

    this._updateCamera(dt);

    // 邊緣旗標只活一幀
    this.pressed = Object.create(null);
  }

  _updateCamera(dt) {
    this.camDist += (this.camDistTarget - this.camDist) * Math.min(1, 9 * dt);

    const cp = Math.cos(this.camPitch), sp = Math.sin(this.camPitch);
    const target = this._camLook.copy(this.pos);
    target.y += EYE * 0.72;

    const dir = new THREE.Vector3(
      Math.sin(this.camYaw) * cp,
      sp,
      Math.cos(this.camYaw) * cp
    );

    // 從目標往後拉
    let dist = this.camDist;
    const probe = this._camPos.copy(target).addScaledVector(dir, dist);

    // 別讓相機鑽進地形
    const gh = groundHeight(probe.x, probe.z) + 0.9;
    if (probe.y < gh) {
      // 沿著射線往回縮，直到高於地面
      for (let i = 0; i < 8 && dist > 1.2; i++) {
        dist *= 0.82;
        probe.copy(target).addScaledVector(dir, dist);
        if (probe.y >= groundHeight(probe.x, probe.z) + 0.9) break;
      }
      probe.y = Math.max(probe.y, groundHeight(probe.x, probe.z) + 0.9);
    }

    this.camera.position.lerp(probe, Math.min(1, 18 * dt));
    this.camera.lookAt(target);
  }

  get speedH() {
    return Math.hypot(this.vel.x, this.vel.z);
  }
}
