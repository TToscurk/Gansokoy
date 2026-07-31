// 戰鬥控制器 —— 日之呼吸十三型輪迴。
//
// 流程：按攻擊 → 上一招演完了沒 → 出招（型錄輪到下一型）→
//   ① 玩家轉向相機前方、給突進衝量
//   ② SlashFX 放橘藍斬弧 + 破空聲
//   ③ 命中判定（扇形）→ 擊飛/擊殺 → 火花、連擊、重擊頓挫
//   ④ UI 閃型名
//
// 動作分兩層：
//   姿勢    每型自己的關鍵影格在 motion.js，這裡只問 poseFor() 要當幀姿勢，
//           寫進 rig 時必須在 player.update()（裡面跑 animateCharacter）之後，
//           才壓得過走路動畫。
//   刀身    刀鞘固定在腰上，刀身每幀重算：收鞘時貼著鞘、出鞘時跟著右手。
//           拔刀過程用 pose.attach 在兩者之間內插，pose.slide 讓刀沿鞘軸滑出。

import * as THREE from 'three';
import { FORMS } from './forms.js';
import { poseFor, applyPose, NEUTRAL } from './motion.js';
import { BLADE_LEN } from '../entities/model.js';

// 握把：掌心落在刀身座標的哪一點。柄從原點（鍔）往 -Y 延伸 0.32m，
// 取中段一點才握得穩。
const GRIP = new THREE.Vector3(0, -0.17, 0.01);
const SHEATH_PULL = 0.55;      // 鞘引き的行程

// 出招／動作倍速。出招門檻就是「動作演完沒」，所以這一個數字同時決定
// 動畫快慢與連打節奏 —— 招式資料表的 dur 全部除以它。
const ATTACK_SPEED = 2;
const CHARGE_TIME = 2.5;       // 左鍵按住幾秒觸發大招
const ULT_LEAD = 0.30;         // 大招的起手空拍（讓招名讀得到、也是蓄勢）
// 超過這個水平速度就切成疾走架式。一般走路 6.4 m/s、疾走 17.7 m/s，
// 取 8.5 剛好只在真的衝刺時才觸發。
const RUN_POSE_SPEED = 8.5;

// 刀光只取刀身外側那一段：整條刀身 1m 寬的 additive 帶子在近相機會蓋屏
// （斬弧當年就踩過），取外 55% 反而更像真的刀光。
const TRAIL_IN = BLADE_LEN * 0.45;
const TRAIL_OUT = BLADE_LEN + 0.09;
const SHEATHE_IDLE = 5.0;      // 幾秒沒出招就自動納刀
const DRAW_DUR = 0.55;
const SHEATHE_DUR = 0.60;

// 每幀重算刀身用的暫存體（避免每幀 new）
const _m = new THREE.Matrix4();
const _g = new THREE.Vector3();
const _e = new THREE.Euler();
const _p = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _p2 = new THREE.Vector3();
const _q2 = new THREE.Quaternion();
const _s = new THREE.Vector3();
const _ta = new THREE.Vector3();
const _tb = new THREE.Vector3();

export class Combat {
  constructor(player, mobs, fx, audio, ui) {
    this.player = player;
    this.mobs = mobs;
    this.fx = fx;
    this.audio = audio;
    this.ui = ui;              // { formBanner(name), combo(n) }

    this.formIndex = 0;        // 下一招要出的型
    this.animT = -1;           // 動作進度（-1 = 沒在動）＝ 唯一的出招門檻
    this.animDur = 0.4;
    this.motion = null;        // 當前動作名（motion.js 的鍵）

    this.comboN = 0;
    this.comboTimer = 0;
    this.hitstop = 0;          // >0 時 main.js 把 dt 壓小，做頓挫

    this.drawn = false;        // 刀出鞘了沒
    this.idleT = 0;            // 沒出招的時間，用來自動納刀
    this.time = 0;

    this.runPhase = 0;         // 疾走循環動作的相位
    this.charging = false;     // 左鍵按住中
    this.chargeT = 0;
    this.ult = null;           // 大招進行中：{ i, needDraw }

    this.stats = { swings: 0, hits: 0, kills: 0 };

    // 技能系統（src/combat/skills.js）掛上來的修正器。沒掛就是純粹的
    // 十三型連段，行為跟以前一模一樣 —— 沒有技能的角色不受影響。
    // 介面：{ dmgMul(ctx) → number, onHit(ctx), onSwing(ctx) }
    this.mods = null;

    // 前臂/手掌是靜態節點，矩陣只需要算一次
    const rig = player.model.userData.rig;
    rig?.foreR?.updateMatrix();
    rig?.handR?.updateMatrix();
  }

  get currentForm() { return FORMS[this.formIndex]; }
  get hasKatana() { return !!this.player.model.userData.rig?.blade; }

  /** 出不出得了招 —— 唯一的限制是「上一招的動作還沒演完」。
   *  沒有額外冷卻：點擊即出招，節奏完全由各型的 dur 決定。 */
  get busy() { return this.animT >= 0; }

  /** 疾走中？用速度判定而不是讀按鍵，這樣被地形/碰撞拖慢時動作也會跟著收。
   *  只有帶刀的角色會擺居合走り的架式（沒刀的人扶什麼刀）。 */
  _running() {
    const p = this.player;
    return this.hasKatana && p.grounded && !p.flying && p.speedH > RUN_POSE_SPEED;
  }

  /** 播一段動作（招式或拔刀/納刀）。 */
  _play(name, dur) {
    this.motion = name;
    this.animT = 0;
    this.animDur = dur;
  }

  /** 手動拔刀／納刀（R 鍵）。回傳新的狀態，沒刀或動作中回 null。 */
  toggleSheath() {
    if (!this.hasKatana || this.animT >= 0) return null;
    if (this.drawn) {
      this._play('sheathe', SHEATHE_DUR);
      this.drawn = false;
    } else {
      this._play('draw', DRAW_DUR);
      this.drawn = true;
    }
    return this.drawn;
  }

  /** 嘗試出招。回傳實際使出的型（上一招還沒演完就回 null）。 */
  tryAttack() {
    const p = this.player;
    if (this.busy || this.ult || !p.enabled) return null;

    const form = FORMS[this.formIndex];
    this.formIndex = (this.formIndex + 1) % FORMS.length;
    return this._execForm(form);
  }

  /**
   * 實際使出一型 —— 轉向、突進、特效、命中、動作、UI。
   * 普通攻擊與大招的每一段都走這裡，兩邊的手感才不會分岔。
   */
  _execForm(form, dmgMul = 1) {
    const p = this.player;
    const wasSheathed = !this.drawn;      // 拔刀術的被動要知道這一刀是不是拔刀斬
    this.idleT = 0;
    this.stats.swings++;
    this.mods?.onSwing?.({ form, wasSheathed });

    // 朝向：相機水平前方（跟 WASD 的「前」同一套定義）
    const fx = -Math.sin(p.camYaw), fz = -Math.cos(p.camYaw);
    p.yaw = Math.atan2(fx, fz);
    p.model.rotation.y = p.yaw;

    // 突進/後撤衝量
    p.vel.x += fx * form.lunge * 4.5;
    p.vel.z += fz * form.lunge * 4.5;

    // 特效與音效。有刀的角色走刀光（每幀由刀身位置生成），
    // 沒刀的（靈夢、魔理沙…）還是用腳下的固定扇形。
    if (this.hasKatana) this.fx.beginTrail(form, p.pos, p.yaw);
    else this.fx.slash(p.pos, p.yaw, form);
    this.audio.swing(form);          // 整個型丟給音效層自己判斷輕重與火焰強度

    // 命中判定。傷害 = 型的基礎值 × 技能倍率 × 被動修正（爆擊、斑紋…）。
    // 修正器每一擊只問一次，所以同一刀砍中的每一隻吃到的倍率一致 ——
    // 不然一群怪裡會有幾隻莫名其妙特別痛。
    const mod = this.mods?.dmgMul?.({ form, wasSheathed }) ?? { mul: 1, crit: false };
    const total = form.dmg * dmgMul * (mod.mul ?? 1);
    const hits = this.mobs.inSector(p.pos, p.yaw, form.range, form.arc);
    for (const m of hits) {
      const dx = m.pos.x - p.pos.x, dz = m.pos.z - p.pos.z;
      const d = Math.hypot(dx, dz) || 1;
      const killed = this.mobs.damage(m, total, dx / d, dz / d);
      this.fx.hit(m.pos);
      if (killed) {
        this.fx.burst(m.pos);
        this.stats.kills++;
      }
      this.stats.hits++;
      this.comboN++;
    }
    if (hits.length) {
      this.mods?.onHit?.({ form, crit: mod.crit, count: hits.length });
      if (mod.crit) this.ui.crit?.();
      this.comboTimer = 3;
      this.ui.combo(this.comboN);
      if (form.heavy || form.finisher || mod.crit || this.comboN % 10 === 0) {
        this.hitstop = form.finisher ? 0.14 : (mod.crit ? 0.1 : 0.07);
      }
    }

    // 動作：刀還在鞘裡就是居合拔刀斬——這一刀既是拔刀也是這一型的攻擊
    if (this.hasKatana && !this.drawn) {
      this.drawn = true;
      this._play('draw', DRAW_DUR / ATTACK_SPEED);
    } else {
      this._play(form.motion, form.dur / ATTACK_SPEED);
    }

    this.ui.formBanner(form.name);
    return form;
  }

  // --- 大招：日之呼吸・全型（壹之型一路連到拾參之型） -------------------
  //
  // 按住左鍵蓄力 CHARGE_TIME 秒觸發。十三型沒有間隔地連續放完，
  // 中途不能被普通攻擊插隊，也不會自動納刀。

  /** 左鍵按下：開始蓄力（普通攻擊由 main.js 另外呼叫 tryAttack）。 */
  holdStart() {
    if (this.ult || !this.player.enabled) return;
    this.charging = true;
    this.chargeT = 0;
  }

  /** 左鍵放開／失去焦點：取消蓄力。 */
  holdEnd() {
    this.charging = false;
    this.chargeT = 0;
  }

  /** 蓄力進度 0~1，給 UI 畫條用。 */
  get chargeRatio() {
    return this.charging ? Math.min(1, this.chargeT / CHARGE_TIME) : 0;
  }

  get ultimate() { return !!this.ult; }

  _startUltimate() {
    this.charging = false;
    this.chargeT = 0;
    // lead＝起手停頓：不留這一拍的話，「日之呼吸・全型」的橫幅會在同一幀
    // 就被壹之型蓋掉，玩家根本看不到大招的名字。
    // 刀還在鞘裡就先拔（拔刀本身不算十三型的一段）
    this.ult = { i: 0, lead: true, needDraw: this.hasKatana && !this.drawn };
    this.ui.formBanner('日之呼吸・全型');
    this.audio.swing(true);
  }

  /** 推進大招的下一段。上一段的動作演完時才呼叫。 */
  _ultStep() {
    if (this.ult.lead) {
      this.ult.lead = false;
      this._play(this.drawn ? 'guard' : 'stand', ULT_LEAD);
      return;
    }
    if (this.ult.needDraw) {
      this.ult.needDraw = false;
      this.drawn = true;
      this._play('draw', DRAW_DUR / ATTACK_SPEED);
      return;
    }
    if (this.ult.i >= FORMS.length) { this.ult = null; return; }
    this._execForm(FORMS[this.ult.i++]);
    // 大招結束後，普通攻擊從壹之型重新輪
    if (this.ult && this.ult.i >= FORMS.length) this.formIndex = 0;
  }

  /**
   * 指定使出某一型 —— 技能系統的入口。
   * 跟普通攻擊走同一條 _execForm，手感與動畫才不會分岔。
   * @param {number} formIndex forms.js 的索引
   * @param {number} [dmgMul=1] 這一招的傷害倍率
   * @returns {boolean} 有沒有真的出招（上一招還沒演完就出不了）
   */
  useForm(formIndex, dmgMul = 1) {
    if (this.busy || this.ult || !this.player.enabled) return false;
    const form = FORMS[formIndex];
    if (!form) return false;
    this._execForm(form, dmgMul);
    return true;
  }

  /** @param dt 受頓挫壓慢的時間；@param rawDt 真實時間（只給 hitstop 自己倒數用） */
  update(dt, rawDt = dt) {
    this.time += dt;
    if (this.hitstop > 0) this.hitstop -= rawDt;

    // 連擊倒數
    if (this.comboTimer > 0) {
      this.comboTimer -= dt;
      if (this.comboTimer <= 0) {
        this.comboN = 0;
        this.ui.combo(0);
      }
    }

    // --- 蓄力 / 大招推進 ---
    // 蓄力用真實時間算，玩家看到的讀條才不會被頓挫拖慢。
    if (this.charging && !this.ult) {
      if (!this.player.enabled) this.holdEnd();
      else {
        this.chargeT += rawDt;
        if (this.chargeT >= CHARGE_TIME) this._startUltimate();
      }
    }
    this.ui.charge?.(this.chargeRatio);
    if (this.ult && this.animT < 0) this._ultStep();

    const rig = this.player.model.userData.rig;
    if (!rig) return;

    // --- 決定這一幀的姿勢 ---
    let pose;
    if (this.animT >= 0) {
      this.animT += dt;
      const k = this.animT / this.animDur;
      if (k >= 1) {
        pose = poseFor(this.motion, 1);
        this.animT = -1;
        this.motion = null;
      } else {
        pose = poseFor(this.motion, k);
      }
    } else if (this._running()) {
      // 疾走：踏步相位由速度換算，跑越快腳步越密
      const cad = Math.min(3.6, Math.max(1.2, this.player.speedH / 5.2));
      this.runPhase = (this.runPhase + dt * cad) % 1;
      pose = poseFor(this.drawn ? 'runDrawn' : 'run', this.runPhase);
    } else if (this.drawn) {
      // 持刀待機：正眼架式 + 一點呼吸起伏
      pose = poseFor('guard', 0);
      const br = Math.sin(this.time * 1.5) * 0.035;
      pose.aR[0] += br;
      pose.wrist[0] += br * 1.4;
    } else {
      pose = NEUTRAL;
    }

    applyPose(rig, pose);

    // --- 自動納刀（大招連段中間會有一幀空檔，別讓它誤觸發） ---
    if (this.drawn && this.animT < 0 && !this.ult) {
      this.idleT += dt;
      if (this.idleT > SHEATHE_IDLE) {
        this.idleT = 0;
        this.drawn = false;
        this._play('sheathe', SHEATHE_DUR);
      }
    } else if (!this.drawn) {
      this.idleT = 0;
    }

    this._updateBlade(pose);

    // 刀光：把刀身真正掃過的位置餵給特效。只在出招時做 ——
    // updateMatrixWorld 是一次角色骨架的走訪，沒必要每幀白花。
    if (this.animT >= 0 && this.drawn && rig.blade) {
      this.player.model.updateMatrixWorld(true);
      rig.blade.localToWorld(_ta.set(0, TRAIL_IN, 0));
      rig.blade.localToWorld(_tb.set(0, TRAIL_OUT, 0));
      this.fx.traceBlade(_ta, _tb);
    }
  }

  /**
   * 刀身姿勢＝在「鞘中（可沿鞘軸滑出）」與「握在右手」之間依 attach 內插。
   * 兩者都算在 body 座標系，因為 blade 掛在 body 底下。
   */
  _updateBlade(pose) {
    const rig = this.player.model.userData.rig;
    const blade = rig.blade;
    if (!blade) return;

    const sh = blade.userData.sheathed;
    // 招式動作不談刀在哪（它們都是出鞘狀態下才播的），沒寫就沿用當前狀態；
    // 只有 draw/sheathe 會明確寫 attach 去搬動刀身。
    const attach = pose.attach ?? (this.drawn ? 1 : 0);

    // 鞘引き：刀身 0.98m 比整條手臂還長，光靠手拉絕對拔不出來 ——
    // 真實居合是左手同時把鞘往後推。這裡就照做：鞘沿自身 +Y 後退，
    // 刀身留在原位，看起來就是刀從鯉口滑出來。
    const pull = pose.slide ?? 0;
    if (rig.sheath) {
      const base = rig.sheath.userData.base;
      rig.sheath.position.copy(base.pos)
        .add(_g.set(0, pull * SHEATH_PULL, 0).applyQuaternion(base.quat));
    }

    _q.copy(sh.quat);
    _p.copy(sh.pos);

    if (attach > 0 && rig.handR) {
      // 手上：位置跟著手掌走，朝向直接由 wrist 指定（軀幹空間）。
      //
      // 刻意不把刀綁死成手掌的子物件 —— 那樣手臂一揮下去，刀就會跟著手掌
      // 多轉 90 度折進地板，每一格都要反推補償角度才寫得出來。
      // 現在 wrist 是「刀身在軀幹空間的絕對朝向」（0=刀尖朝下、1.57=水平前指、
      // 3.14=朝天），寫招式時所見即所得。
      rig.armR.updateMatrix();
      _m.copy(rig.armR.matrix).multiply(rig.foreR.matrix).multiply(rig.handR.matrix);
      _p2.setFromMatrixPosition(_m);                       // 掌心（軀幹空間）

      const w = pose.wrist || NEUTRAL.wrist;
      _q2.setFromEuler(_e.set(Math.PI - w[0], w[1], w[2]));
      // 柄在刀原點的 -Y 側，把原點沿刀身推出去，纏繩段才落在掌心
      _p2.add(_g.copy(GRIP).negate().applyQuaternion(_q2));

      if (attach >= 1) { _p.copy(_p2); _q.copy(_q2); }
      else { _p.lerp(_p2, attach); _q.slerp(_q2, attach); }
    }

    blade.position.copy(_p);
    blade.quaternion.copy(_q);
  }
}
