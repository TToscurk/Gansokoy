/**
 * 區域偵測 —— 任務的 onEnter 觸發靠這個。
 *
 * ## 為什麼需要這層
 *
 * 任務資料（quests/data.js）是為原本 17 張圖的幻想鄉寫的，它的 onEnter
 * 指向 'shrine' / 'moriya' / 'myouren' / 'sdm' 這些**地圖**。這個移植版只有
 * 神社一張圖，那些地圖不存在，對應的任務步驟就永遠觸發不了。
 *
 * 解法是別名，不是改任務資料：ZONES 用同一組 id 在神社境內圈出區域，
 * 任務引擎照樣收到 onEnter('moriya')，完全不知道自己身在何處。
 * 之後真正的地圖接回來時，把這張表換成真的地圖切換即可，
 * quests/data.js 一個字都不用動。
 *
 * 境內的三處「神社」是真的有立物件的（本殿 + 兩座摂社），不是純座標
 * ——摂社本來就是神社境內的小社，境內三社巡禮站得住腳。
 *
 * ## 座標
 * 神社的世界座標：參道往 +Z，拜殿在 -Z。台地 y=3.2，前庭 y=0。
 * 角色與物件的位置目前都是暫定的，之後會搬 —— 所以這裡只放區域定義，
 * 不要把任何角色位置寫進來。
 */

/**
 * 每個區域是一個圓（中心 + 半徑）。圓比方框好用：玩家從任何方向靠近
 * 都會在差不多的距離觸發，不會因為擦著邊走而漏掉。
 */
export const ZONES = [
  {
    id: 'shrine',
    zh: '博麗神社',
    x: 0, z: -6, r: 11,
    note: '拜殿與台地中心',
  },
  {
    id: 'moriya',
    zh: '摂社・守矢',
    x: -22, z: 2, r: 5.5,
    note: '境內西側的摂社（守矢神社的分社）',
  },
  {
    id: 'myouren',
    zh: '摂社・命蓮',
    x: 22, z: 2, r: 5.5,
    note: '境內東側的摂社（命蓮寺的分社）',
  },
  {
    id: 'sdm',
    zh: '紅魔館方向的鳥居',
    x: 0, z: 34, r: 7,
    note: '外鳥居。主線一章要往紅魔館，這個移植版沒有那張圖，' +
          '暫時以「走出外鳥居＝啟程前往」代替。',
  },
];

/**
 * 進出區域的追蹤器。只在「跨進一個新區域」時回報一次，
 * 站在原地不會每幀重複觸發。
 */
export class ZoneTracker {
  constructor(zones = ZONES) {
    this.zones = zones;
    this.current = null;        // 目前所在區域 id（不在任何區域時為 null）
    this.onEnter = null;        // (zoneId, zone) => void
  }

  /** 回傳這個座標所在的區域（重疊時取圓心最近的那個），沒有則 null */
  zoneAt(x, z) {
    let best = null, bestD = Infinity;
    for (const zone of this.zones) {
      const d = Math.hypot(x - zone.x, z - zone.z);
      if (d <= zone.r && d < bestD) { bestD = d; best = zone; }
    }
    return best;
  }

  /** 每幀呼叫。跨進新區域時觸發 onEnter。 */
  update(x, z) {
    const zone = this.zoneAt(x, z);
    const id = zone?.id ?? null;
    if (id === this.current) return null;
    this.current = id;
    if (zone) this.onEnter?.(zone.id, zone);
    return zone;
  }
}
