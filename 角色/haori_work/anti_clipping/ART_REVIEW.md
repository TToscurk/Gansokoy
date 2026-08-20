# Yoriichi Haori v2.1 Visual Anti-Clipping Review

Status: analysis prototype only. `yoriichi_character_v21.tscn` and all official Body/Haori assets remain unchanged.

Comparison order in every contact sheet is: original, 2 cm, 3 cm, 4 cm.

## Body sleeve-interior mask

- Left arm/forearm: 3,626 vertices.
- Right arm/forearm: 3,631 vertices.
- 14,272 faces are omitted in the experimental Body export.
- The mask spans 16% to 95% of the Arm-to-Hand rest segment, with an 8.5 cm maximum radial envelope.
- Hand-dominant vertices and shoulder-dominant vertices are excluded, so palms, the required wrist transition, shoulder caps, and neck remain visible.
- UV, material, Body skeleton, weights outside the omitted surface, and animations are unchanged.

Runtime result: the large forearm/skin patches visible through the sleeve are removed in the masked candidates. Full hands can still cross the sleeve wall in extreme Run/Turn/Draw frames; hiding additional hand geometry would violate the requested visible-hand boundary and is not recommended.

## Haori hem clearance

The lower hem/side panels were displaced outwards along their oriented vertex normals with a height falloff. Each candidate changes 29,055 vertices while preserving topology, UV, material, 33-bone Haori rig, weights, animations, and SpringBone settings.

| Candidate | Average displacement | Maximum displacement | Visual result |
| --- | ---: | ---: | --- |
| 2 cm | 1.8048 cm | 2 cm | Insufficient; obvious hakama shards remain in Draw and stride views. |
| 3 cm | 2.7072 cm | 3 cm | Improved; narrow residual penetration remains. |
| 4 cm | 3.6096 cm | 4 cm | Best of the three; reviewed frames no longer show the large side/back hakama penetration, and idle silhouette remains acceptable. |

The knee/leg visible through the intentional front opening is not treated as clipping and was not sealed.

## Recommendation

Use the experimental sleeve-interior Body mask plus the 4 cm hem-clearance geometry as the next production candidate. Do not claim full ART approval yet: the remaining palm-through-sleeve-wall cases need a sleeve aperture/cuff geometry or sleeve weighting review, not more SpringBone stiffness, drag, or collider tuning.

## Runtime invariants

- Body Skeleton3D scale: `(1, 1, 1)`.
- Haori Skeleton3D scale: `(1, 1, 1)`.
- SpringBoneSimulator3D scale: `(1, 1, 1)`.
- SpringBone chains: 9, unchanged.
- SpringBone colliders: 8, unchanged.
- Anchor coupling: 10 anchors, unchanged.
