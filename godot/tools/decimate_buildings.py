#!/usr/bin/env python3
"""Decimate the high-poly Meshy building GLBs into LOD versions.

WHY: measured on 2026-09-03, 96 building instances carry 49.06M triangles and
account for 51-60% of GPU frame time in maps/slice (18 fps -> 38 fps when
hidden). Godot's import-time LOD chain saturates: raising mesh_lod_threshold
from 1px to 64px only drops 92M -> 64M tris, so the engine cannot fix this.

SAFETY (project constitution): source GLBs under assets/machiya/ are READ-ONLY.
Output goes to a separate directory. Nothing here overwrites a commissioned
asset, and no scene is modified -- wiring is a separate, approved step.

Approach: parse the GLB container ourselves and rewrite only the mesh
primitive buffers. Using pygltflib to reason about structure + numpy for the
buffer surgery keeps materials, textures, node transforms, and the scene graph
byte-identical; only POSITION/NORMAL/TEXCOORD/indices are replaced. That
matters because the buildings' look lives in their PBR textures, not their
polygon density.
"""
from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

import numpy as np
import fast_simplification
from pygltflib import GLTF2
from scipy.spatial import cKDTree

# glTF component types we may encounter for indices.
_COMP = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32}
_NUM_COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
_COMP_DTYPE = {5120: np.int8, 5121: np.uint8, 5122: np.int16,
               5123: np.uint16, 5125: np.uint32, 5126: np.float32}


def _blob(gltf: GLTF2) -> bytes:
    return gltf.binary_blob()


def read_accessor(gltf: GLTF2, blob: bytes, idx: int) -> np.ndarray:
    acc = gltf.accessors[idx]
    view = gltf.bufferViews[acc.bufferView]
    dtype = _COMP_DTYPE[acc.componentType]
    ncomp = _NUM_COMPONENTS[acc.type]
    itemsize = np.dtype(dtype).itemsize * ncomp
    start = (view.byteOffset or 0) + (acc.byteOffset or 0)
    stride = view.byteStride or itemsize

    if stride == itemsize:
        raw = blob[start:start + itemsize * acc.count]
        arr = np.frombuffer(raw, dtype=dtype, count=acc.count * ncomp)
    else:
        # Interleaved vertex buffer: gather element by element.
        out = np.empty(acc.count * ncomp, dtype=dtype)
        for i in range(acc.count):
            off = start + i * stride
            out[i * ncomp:(i + 1) * ncomp] = np.frombuffer(
                blob[off:off + itemsize], dtype=dtype, count=ncomp)
        arr = out
    return arr.reshape(acc.count, ncomp) if ncomp > 1 else arr


def decimate_glb(src: Path, dst: Path, target_tris: int, verbose: bool = True):
    gltf = GLTF2().load(str(src))
    blob = _blob(gltf)

    total_before = 0
    total_after = 0

    # Accumulate rebuilt binary data; every primitive gets fresh buffer views
    # appended, and old ones are simply orphaned (the exporter repacks).
    new_chunks: list[bytes] = [blob]
    cursor = len(blob)

    def append(data: bytes) -> int:
        nonlocal cursor
        pad = (-len(data)) % 4
        data = data + b"\x00" * pad
        new_chunks.append(data)
        off = cursor
        cursor += len(data)
        return off

    for mesh in gltf.meshes:
        for prim in mesh.primitives:
            if prim.indices is None or prim.mode not in (None, 4):
                continue
            pos_idx = prim.attributes.POSITION
            if pos_idx is None:
                continue

            idx = read_accessor(gltf, blob, prim.indices).astype(np.uint32).ravel()
            pos = read_accessor(gltf, blob, pos_idx).astype(np.float32)
            tris_before = len(idx) // 3
            total_before += tris_before

            faces = idx.reshape(-1, 3)
            # Per-primitive target, proportional to this primitive's share of
            # the model, so one dense surface cannot eat the whole budget.
            keep = max(0.02, min(1.0, target_tris / max(total_all(gltf, blob), 1)))
            want = max(12, int(tris_before * keep))

            if want >= tris_before:
                total_after += tris_before
                continue

            verts_out, faces_out = fast_simplification.simplify(
                pos, faces, 1.0 - (want / tris_before))

            tris_after = len(faces_out)
            total_after += tris_after
            if verbose:
                print(f"    surface {tris_before:>8,} -> {tris_after:>8,}")

            # fast_simplification collapses vertices, so UV/normal accessors no
            # longer line up. Rebuild NORMAL from geometry and resample UV by
            # nearest source vertex -- the textures are the whole look here, so
            # UVs must survive even approximately rather than be dropped.
            verts_out = verts_out.astype(np.float32)
            faces_out = faces_out.astype(np.uint32)

            new_attrs = {}
            off = append(verts_out.tobytes())
            new_attrs["POSITION"] = _mk_accessor(
                gltf, off, verts_out.nbytes, len(verts_out), 5126, "VEC3",
                mins=verts_out.min(axis=0).tolist(),
                maxs=verts_out.max(axis=0).tolist())

            nrm = _face_normals(verts_out, faces_out)
            off = append(nrm.tobytes())
            new_attrs["NORMAL"] = _mk_accessor(
                gltf, off, nrm.nbytes, len(nrm), 5126, "VEC3")

            for uv_name in ("TEXCOORD_0", "TEXCOORD_1"):
                src_uv_idx = getattr(prim.attributes, uv_name, None)
                if src_uv_idx is None:
                    continue
                src_uv = read_accessor(gltf, blob, src_uv_idx).astype(np.float32)
                uv = _resample(pos, src_uv, verts_out)
                off = append(uv.tobytes())
                new_attrs[uv_name] = _mk_accessor(
                    gltf, off, uv.nbytes, len(uv), 5126, "VEC2")

            flat = faces_out.ravel().astype(np.uint32)
            off = append(flat.tobytes())
            new_idx = _mk_accessor(gltf, off, flat.nbytes, len(flat), 5125, "SCALAR")

            for k, v in new_attrs.items():
                setattr(prim.attributes, k, v)
            # Tangents referenced stale vertices; Godot regenerates them on
            # import (meshes/ensure_tangents=true).
            prim.attributes.TANGENT = None
            prim.indices = new_idx
            prim.targets = None

    gltf.set_binary_blob(b"".join(new_chunks))
    _repack(gltf)
    dst.parent.mkdir(parents=True, exist_ok=True)
    gltf.save_binary(str(dst))
    return total_before, total_after


def _repack(gltf: GLTF2) -> None:
    """Drop orphaned buffer data left behind by the rewrite.

    The old high-poly vertex/index views are still in the blob after we point
    the primitives at new accessors; without this the output GLB is LARGER than
    the source (measured 73.8 MB vs 72.8 MB) even though it holds 2% of the
    geometry. Rebuild the blob from only the views still referenced.
    """
    blob = gltf.binary_blob()
    used = sorted({a.bufferView for a in gltf.accessors
                   if a.bufferView is not None}
                  | {i.bufferView for i in (gltf.images or [])
                     if i.bufferView is not None})
    remap: dict[int, int] = {}
    chunks: list[bytes] = []
    cursor = 0
    new_views = []
    from pygltflib import BufferView
    for old in used:
        v = gltf.bufferViews[old]
        start = v.byteOffset or 0
        data = blob[start:start + v.byteLength]
        pad = (-len(data)) % 4
        chunks.append(data + b"\x00" * pad)
        nv = BufferView(buffer=0, byteOffset=cursor, byteLength=v.byteLength)
        # byteStride only remains valid for views we did not rewrite.
        if v.byteStride:
            nv.byteStride = v.byteStride
        if v.target is not None:
            nv.target = v.target
        new_views.append(nv)
        remap[old] = len(new_views) - 1
        cursor += len(data) + pad

    for a in gltf.accessors:
        if a.bufferView is not None:
            a.bufferView = remap[a.bufferView]
    for i in (gltf.images or []):
        if i.bufferView is not None:
            i.bufferView = remap[i.bufferView]

    gltf.bufferViews = new_views
    gltf.set_binary_blob(b"".join(chunks))
    if gltf.buffers:
        gltf.buffers[0].byteLength = cursor


_TOTAL_CACHE: dict[int, int] = {}


def total_all(gltf: GLTF2, blob: bytes) -> int:
    key = id(gltf)
    if key in _TOTAL_CACHE:
        return _TOTAL_CACHE[key]
    t = 0
    for mesh in gltf.meshes:
        for prim in mesh.primitives:
            if prim.indices is None:
                continue
            acc = gltf.accessors[prim.indices]
            t += acc.count // 3
    _TOTAL_CACHE[key] = t
    return t


def _face_normals(verts: np.ndarray, faces: np.ndarray) -> np.ndarray:
    nrm = np.zeros_like(verts)
    v0, v1, v2 = verts[faces[:, 0]], verts[faces[:, 1]], verts[faces[:, 2]]
    fn = np.cross(v1 - v0, v2 - v0)
    for i in range(3):
        np.add.at(nrm, faces[:, i], fn)
    ln = np.linalg.norm(nrm, axis=1, keepdims=True)
    ln[ln == 0] = 1.0
    return (nrm / ln).astype(np.float32)


def _resample(src_pos: np.ndarray, src_val: np.ndarray,
              dst_pos: np.ndarray) -> np.ndarray:
    """Nearest-source-vertex resample via KD-tree.

    A brute-force distance matrix is O(dst x src) and does not finish on these
    models (915k source verts): the first attempt ran past 7 minutes on one
    building. cKDTree turns it into O(dst log src) -- seconds.
    """
    tree = cKDTree(src_pos)
    _, nearest = tree.query(dst_pos, k=1, workers=-1)
    return src_val[nearest].astype(np.float32)


def _mk_accessor(gltf, offset, length, count, comp_type, acc_type,
                 mins=None, maxs=None) -> int:
    from pygltflib import Accessor, BufferView
    gltf.bufferViews.append(BufferView(buffer=0, byteOffset=offset,
                                       byteLength=length))
    acc = Accessor(bufferView=len(gltf.bufferViews) - 1, byteOffset=0,
                   componentType=comp_type, count=count, type=acc_type)
    if mins is not None:
        acc.min, acc.max = mins, maxs
    gltf.accessors.append(acc)
    return len(gltf.accessors) - 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("dst", type=Path)
    ap.add_argument("--target", type=int, default=20000,
                    help="target triangle count for the whole model")
    a = ap.parse_args()
    print(f"[decimate] {a.src.name} -> target {a.target:,} tris")
    before, after = decimate_glb(a.src, a.dst, a.target)
    print(f"[decimate] {before:,} -> {after:,} tris "
          f"({100.0 * after / max(before,1):.1f}%)  saved to {a.dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
