// 神社專用：把角色放到參道上，繞過地區座標系統。
//
// gensokyo-3d 的角色原本散佈在整個幻想鄉地圖上；
// shrine 只有一張神社圖，所以這裡為每位角色計算一個展列用的位置。
//
// 角色是否上場由「擺放狀態表」（placements.js）決定：預設只有繼國緣一
// 站在場上，其餘角色收在角色場景編輯器（src/ui/scene-editor.js）的面板
// 裡，之後由玩家自己拖曳出來放置。擺放只在本次遊玩期間有效。
import { ROSTER } from './roster.js';
import { NPCManager, TALK_RANGE } from './npc.js';
import { getPlacements, setPlacement, removePlacement } from './placements.js';

/**
 * 站位。原本是 10 欄方陣排在參道上，看起來像角色選單而不是神社 ——
 * 改成沿著境內幾個「會有人待著」的地點分群：拜殿前、手水舍、繪馬掛、
 * 石階兩側、樹下。每個點給一個半徑，同群的人繞著散開並各自轉向。
 *
 * 現在只用來算繼國緣一的預設站位（見下方 seedDefaultPlacement），
 * 其餘角色的位置全部交給編輯器。
 *
 * 參道中線（|x| < 3.2）永遠留空，不然玩家一路上都在撞人。
 */
const SPOTS = [
  { x: -8.5, z: -0.5, r: 3.0, face: Math.PI * 0.85 },  // 拜殿前・左
  { x: 8.5, z: -0.5, r: 3.0, face: Math.PI * 1.15 },   // 拜殿前・右
  { x: 13.0, z: 5.5, r: 2.8, face: Math.PI * 1.35 },   // 手水舍
  { x: -13.5, z: 2.5, r: 2.6, face: Math.PI * 0.6 },   // 繪馬掛
  { x: -11.0, z: 9.5, r: 3.2, face: Math.PI },         // 鳥居內・左
  { x: 11.0, z: 9.5, r: 3.2, face: Math.PI },          // 鳥居內・右
  { x: -9.0, z: 18.0, r: 3.0, face: Math.PI * 0.9 },   // 石階上・左
  { x: 9.0, z: 18.0, r: 3.0, face: Math.PI * 1.1 },    // 石階上・右
  { x: -10.5, z: 30.0, r: 3.4, face: Math.PI },        // 階下・左
  { x: 10.5, z: 30.0, r: 3.4, face: Math.PI },         // 階下・右
  { x: -8.0, z: 41.0, r: 3.0, face: Math.PI * 0.95 },  // 外鳥居旁
  { x: 8.0, z: 41.0, r: 3.0, face: Math.PI * 1.05 },
];

/** 決定性的偽亂數 —— 同一個 index 每次重整都站在同一個地方 */
function rand(seed) {
  const v = Math.sin(seed * 127.1 + 311.7) * 43758.5453;
  return v - Math.floor(v);
}

const PATH_HALF_WIDTH = 3.2;

/** 把第 index 位安排到某個聚集點附近 */
function spotPos(index, heightFn) {
  const spot = SPOTS[index % SPOTS.length];
  const ring = Math.floor(index / SPOTS.length);      // 第幾圈（人多時往外站）

  const a = rand(index * 2.1) * Math.PI * 2;
  const rad = spot.r * (0.35 + 0.65 * rand(index * 3.7)) + ring * 2.1;

  let x = spot.x + Math.cos(a) * rad;
  const z = spot.z + Math.sin(a) * rad * 0.8;

  // 別站到參道正中間擋路
  if (Math.abs(x) < PATH_HALF_WIDTH) x = Math.sign(x || 1) * PATH_HALF_WIDTH;

  const y = heightFn(x, z);
  const face = spot.face + (rand(index * 5.3) - 0.5) * 0.9;
  return { x, y, z, face };
}

const YORIICHI_ID = 'yoriichi';

/**
 * 生出目前有擺放記錄的角色，放到神社場景裡。
 *
 * @param {THREE.Scene} scene
 * @param {(x:number,z:number)=>number} heightFn  神社自己的 heightAt
 * @param {THREE.Scene} [labelScene] 名牌用的 overlay 場景
 * @param {string} [excludeId] 玩家正在扮演的角色 id —— 不要同時放一個 NPC
 */
export function spawnAllNPCs(scene, heightFn, labelScene, excludeId) {
  const mgr = new NPCManager(scene, labelScene);
  const byId = new Map(ROSTER.map(s => [s.id, s]));

  // 預設只有繼國緣一站在場上，其餘角色收進編輯器的面板裡，之後由玩家
  // 自己拖曳出來放置。這裡只在還沒有任何擺放記錄時（模組剛載入）補上他的
  // 預設站位 —— 沿用原本 spotPos 的站位邏輯，用他在 ROSTER 裡的固定索引，
  // 這樣不管 excludeId 是誰，預設站位都一樣。
  if (!(YORIICHI_ID in getPlacements())) {
    const idx = ROSTER.findIndex(s => s.id === YORIICHI_ID);
    if (idx !== -1) {
      const seed = spotPos(idx, heightFn);
      setPlacement(YORIICHI_ID, seed.x, seed.z, seed.face);
    }
  }

  /** 把一筆擺放記錄實際套用到（快取的）角色物件上，需要的話上場 */
  function spawnPlaced(id, entry) {
    const spec = byId.get(id);
    if (!spec) return;              // 擺放表裡有、roster 裡沒有：忽略
    if (id === excludeId) return;   // 玩家正在扮演這位，不要同時上場

    const ground = heightFn(entry.x, entry.z);
    const y = ground + (spec.float ? (spec.floatY ?? 0.8) : 0);

    const rec = mgr._ensure(spec);
    rec.root.position.set(entry.x, y, entry.z);
    rec.plate.position.set(entry.x, y + 2.35, entry.z);
    rec.pos.set(entry.x, y, entry.z);
    rec.baseYaw = entry.face ?? 0;
    rec.root.rotation.y = rec.baseYaw;
    rec.root.visible = true;
    rec.plate.visible = false;

    if (!mgr.npcs.includes(rec)) {
      scene.add(rec.root);
      mgr.labelScene.add(rec.plate);
      mgr.npcs.push(rec);
    }
  }

  for (const [id, entry] of Object.entries(getPlacements())) {
    spawnPlaced(id, entry);
  }

  // ---- 對話狀態機 ----
  let currentNPC = null;
  let talkIndex = 0;
  let currentLines = null;

  return {
    mgr,

    /**
     * 選完角色後呼叫：把玩家扮演的那位從境內撤掉，並讓上一位回場。
     * 角色是在載入時就建好的（很貴），所以這裡只做上下場，不重建。
     */
    setPlayerCharacter(id) {
      // 先讓前一位回場
      if (this._benched) {
        const b = this._benched;
        scene.add(b.root);
        mgr.labelScene.add(b.plate);
        mgr.npcs.push(b);
        this._benched = null;
      }
      const i = mgr.npcs.findIndex(n => n.spec.id === id);
      if (i === -1) return;
      const rec = mgr.npcs[i];
      scene.remove(rec.root);
      mgr.labelScene.remove(rec.plate);
      rec.plate.visible = false;
      mgr.npcs.splice(i, 1);
      if (mgr.nearest === rec) mgr.nearest = null;
      this._benched = rec;
    },
    _benched: null,

    /**
     * 角色場景編輯器用：把一位角色放到（或搬到）場上的某個座標。
     * 對已經在場上的角色再呼叫一次 = 搬移。
     */
    place(id, x, z, face = 0) {
      if (!byId.has(id)) return false;
      if (this._benched && this._benched.spec.id === id) return false;   // 玩家自己扮演中
      setPlacement(id, x, z, face);
      spawnPlaced(id, { x, z, face });
      return true;
    },

    /** 角色場景編輯器用：把一位角色從場上收回面板 */
    unplace(id) {
      removePlacement(id);
      const i = mgr.npcs.findIndex(n => n.spec.id === id);
      if (i === -1) return false;
      const rec = mgr.npcs[i];
      scene.remove(rec.root);
      mgr.labelScene.remove(rec.plate);
      rec.plate.visible = false;
      mgr.npcs.splice(i, 1);
      if (mgr.nearest === rec) mgr.nearest = null;
      return true;
    },

    /** 角色場景編輯器用：目前的擺放記錄 { [id]: {x,z,face} } */
    getPlacements() {
      return getPlacements();
    },

    /** 每幀呼叫 */
    update(t, playerPos, camera) {
      return mgr.update(t, playerPos, camera);
    },

    /** 按 E 時：若靠近 NPC 則回傳一行對話，否則回 null */
    talk(playerPos) {
      const npc = mgr.nearest;
      if (!npc) return null;

      const dist = npc.pos.distanceTo(playerPos);
      if (dist > 5) return null;

      if (currentNPC !== npc) {
        // 新對象，重設對話
        currentNPC = npc;
        currentLines = mgr.nextTalk(npc);
        talkIndex = 0;
      }

      if (talkIndex >= currentLines.length) {
        // 這組講完了
        currentNPC = null;
        currentLines = null;
        talkIndex = 0;
        return null;
      }

      return {
        name: npc.spec.zh,
        title: npc.spec.title,
        line: currentLines[talkIndex++],
        done: talkIndex >= currentLines.length,
      };
    },

    /** 最近 NPC 的名字，給 prompt 顯示用。範圍與實際能否對話一致。 */
    nearestId(playerPos) {
      const npc = mgr.nearest;
      if (!npc) return null;
      if (npc.pos.distanceTo(playerPos) > TALK_RANGE) return null;
      return npc.spec.zh;
    },

    /** 最近 NPC 距離 */
    nearestDist(playerPos) {
      const npc = mgr.nearest;
      if (!npc) return Infinity;
      return npc.pos.distanceTo(playerPos);
    },
  };
}
