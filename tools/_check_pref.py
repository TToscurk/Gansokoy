import bpy
en = sorted(a.module for a in bpy.context.preferences.addons)
ext = [m.split(".")[-1] for m in en if m.startswith("bl_ext.")]
print("PREF total", len(en), "ext", len(ext))
print("PREF sample", ", ".join(sorted(ext)[:12]))
