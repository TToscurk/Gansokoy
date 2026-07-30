// 傳送點的「發光提示點」—— 楓之谷式的低調光點，所有地圖共用。
//
// 依需求刻意不做鳥居／拱門／告示牌之類的裝飾：只有一顆懸浮的光球、
// 一圈地面光環、一道若有似無的光柱。看到光就知道可以走過去按 E。
import * as THREE from 'three';

/**
 * @param {THREE.Object3D} parent 掛在哪（world 群組或 scene）
 * @param {number} x @param {number} y 地面高度 @param {number} z
 * @param {number} [color]
 * @returns {THREE.Group} group.userData.update(t) 每幀呼叫讓它呼吸
 */
export function makePortalGlow(parent, x, y, z, color = 0x8be8ff) {
  const g = new THREE.Group();
  g.position.set(x, y, z);
  parent.add(g);

  const noOutline = (m) => { m.userData.noOutline = true; return m; };

  // 懸浮光球
  const orb = noOutline(new THREE.Mesh(
    new THREE.SphereGeometry(0.16, 12, 10),
    new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.95 })
  ));
  orb.position.y = 1.15;
  g.add(orb);
  const halo = noOutline(new THREE.Mesh(
    new THREE.SphereGeometry(0.34, 12, 10),
    new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.22, blending: THREE.AdditiveBlending, depthWrite: false })
  ));
  halo.position.y = 1.15;
  g.add(halo);

  // 光柱（開口圓柱，加法混合，非常淡）
  const pillar = noOutline(new THREE.Mesh(
    new THREE.CylinderGeometry(0.34, 0.55, 2.6, 14, 1, true),
    new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.1, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide })
  ));
  pillar.position.y = 1.3;
  g.add(pillar);

  // 地面光環
  const ring = noOutline(new THREE.Mesh(
    new THREE.RingGeometry(0.45, 0.8, 26),
    new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.4, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide })
  ));
  ring.rotation.x = -Math.PI / 2;
  ring.position.y = 0.05;
  g.add(ring);

  const light = new THREE.PointLight(color, 7, 9, 2);
  light.position.y = 1.2;
  g.add(light);

  // 環繞的小光屑
  const N = 14;
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(N * 3), 3));
  const sparks = noOutline(new THREE.Points(geo, new THREE.PointsMaterial({
    color, size: 0.05, transparent: true, opacity: 0.8,
    blending: THREE.AdditiveBlending, depthWrite: false, sizeAttenuation: true,
  })));
  g.add(sparks);

  g.userData.update = (t) => {
    const pulse = 0.5 + Math.sin(t * 2.2) * 0.5;
    orb.position.y = 1.15 + Math.sin(t * 1.6) * 0.12;
    halo.position.y = orb.position.y;
    halo.material.opacity = 0.14 + pulse * 0.16;
    ring.material.opacity = 0.28 + pulse * 0.22;
    ring.rotation.z = t * 0.4;
    light.intensity = 5.5 + pulse * 3;
    const p = sparks.geometry.attributes.position;
    for (let i = 0; i < N; i++) {
      const a = t * 0.8 + (i / N) * Math.PI * 2;
      const r = 0.55 + Math.sin(t * 1.3 + i * 2.1) * 0.1;
      p.array[i * 3] = Math.cos(a) * r;
      p.array[i * 3 + 1] = 0.35 + ((t * 0.25 + i * 0.37) % 1) * 1.7;
      p.array[i * 3 + 2] = Math.sin(a) * r;
    }
    p.needsUpdate = true;
  };
  return g;
}
