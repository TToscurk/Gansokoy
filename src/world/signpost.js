// 道標 —— 傳送點旁的木牌，寫目的地名，全地圖共用。
//
// 升級5 的「兩層引導」之二：遠看是目的地剪影與光點，走近讀道標。
// 刻意做成舊木牌（歪一點、字是墨書），不做懸浮 UI —— 世界內的
// 資訊用世界內的東西承載。
//
// 字用 canvas 貼圖：一塊牌一張 128×64，只在建構時畫一次。
// 牌數少（每張圖一到四塊），不需要圖集。

import * as THREE from 'three';

let _woodMat = null, _postMat = null;
function mats() {
  if (!_woodMat) {
    _woodMat = new THREE.MeshStandardMaterial({ color: '#8a6f4d', roughness: 0.95 });
    _postMat = new THREE.MeshStandardMaterial({ color: '#5d4732', roughness: 0.95 });
  }
  return { wood: _woodMat, post: _postMat };
}

function labelTexture(text) {
  const c = document.createElement('canvas');
  c.width = 256; c.height = 96;
  const g = c.getContext('2d');
  // 板面：木色底 + 幾道淡木紋
  g.fillStyle = '#9a7c55';
  g.fillRect(0, 0, 256, 96);
  g.strokeStyle = 'rgba(74,52,32,.28)';
  g.lineWidth = 2;
  for (let y = 12; y < 96; y += 18) {
    g.beginPath(); g.moveTo(0, y + Math.sin(y) * 3); g.lineTo(256, y + Math.cos(y) * 3); g.stroke();
  }
  // 墨書
  g.fillStyle = '#2e2118';
  g.font = '700 34px "Noto Sans TC","Yu Gothic",serif';
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.fillText(text, 128, 50);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  return t;
}

/**
 * @param {THREE.Object3D} world
 * @param {number} x @param {number} y 地面高度 @param {number} z
 * @param {string} text  牌上的字（例：「往 人間之里」）
 * @param {number} [faceYaw=0]  牌面朝向（0 = 面向 +Z 南，跟 controller yaw 同口徑）
 * @returns {THREE.Group}
 */
export function makeSignpost(world, x, y, z, text, faceYaw = 0) {
  const { post } = mats();
  const g = new THREE.Group();
  g.position.set(x, y, z);
  g.rotation.y = faceYaw + Math.PI;   // plank 的正面是 -Z 那一面 → 轉到 faceYaw 方向
  g.rotation.z = ((Math.abs(x * 7 + z * 13) % 5) - 2) * 0.012;   // 微歪，別太整齊（決定性）
  world.add(g);

  const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.055, 0.07, 1.7, 7), post);
  pole.position.y = 0.85;
  pole.castShadow = pole.receiveShadow = true;
  g.add(pole);

  // 微量自發光：道標常立在樹蔭裡（傳送點多在林緣），全靠受光的話
  // 一走進陰影字就黑掉 —— 「走近才看得清」不等於「走近也看不清」。
  const tex = labelTexture(text);
  const plankMat = new THREE.MeshStandardMaterial({
    map: tex, roughness: 0.92,
    emissive: 0xffffff, emissiveMap: tex, emissiveIntensity: 0.32,
  });
  const plank = new THREE.Mesh(new THREE.BoxGeometry(1.15, 0.42, 0.06), plankMat);
  plank.position.set(0, 1.5, 0);
  plank.rotation.z = 0.015;
  plank.castShadow = plank.receiveShadow = true;
  g.add(plank);
  // 側邊小補丁（一根斜撐，看起來是釘上去的）
  const brace = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.3, 0.05), post);
  brace.position.set(0.4, 1.24, -0.03);
  brace.rotation.z = 0.6;
  g.add(brace);
  return g;
}
