"""P13 W7：village_v2.tscn の root 直下末尾に overlay（PackedScene instance）を 1 つ追加する（既に在れば何もしない）。
  python mount_overlay.py <ext_id> <res://…scn> <NodeName>
CRLF／LF は元ファイルのまま保つ（バイナリ読み書き）。ext_resource は最後の ext_resource 行の直後に、node は末尾に追加。
"""
import re
import sys

TSCN = r"D:/神社/shrine/godot/maps/village_v2/village_v2.tscn"


def main():
    ext_id, res_path, node = sys.argv[1:4]
    b = open(TSCN, "rb").read()
    nl = b"\r\n" if b"\r\n" in b[:4000] else b"\n"
    s = b.decode("utf-8")
    if f'name="{node}"' in s:
        print("already mounted:", node)
        return
    if f'id="{ext_id}"' in s:
        raise SystemExit("ext id exists: " + ext_id)
    lines = s.split(nl.decode())
    last_ext = max(i for i, l in enumerate(lines) if l.startswith("[ext_resource "))
    lines.insert(last_ext + 1, f'[ext_resource type="PackedScene" path="{res_path}" id="{ext_id}"]')
    # 末尾：最後の非空行の後に node を足す（ファイルは「…\n\n」で終わる）
    while lines and lines[-1] == "":
        lines.pop()
    lines.append("")
    lines.append(f'[node name="{node}" parent="." instance=ExtResource("{ext_id}")]')
    lines.append("")
    out = nl.decode().join(lines)
    open(TSCN, "wb").write(out.encode("utf-8"))
    print("mounted", node, "as", ext_id)


main()
