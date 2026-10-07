"""Generate R3c capture adapter without modifying sealed R3b helper."""
from pathlib import Path
r=Path(__file__).resolve().parents[1]
g=r/'godot'
s=(g/'tools/shot_p10_activity_candidates.gd').read_text()
s=s.replace('var cam: Camera3D','var cam: Camera3D\nvar overlay: Node3D')
s=s.replace('var pop=world.get_node("Population/PopulationP10")','var pop=world.get_node("Population/PopulationP10")\n overlay=world.get_node_or_null("Population/ActivityP10")\n if overlay==null:\n  overlay=Node3D.new()\n  overlay.set_script(load("res://scripts/npc_activity_overlay.gd"))\n  world.get_node("Population").add_child(overlay)\n for i in 4: await process_frame')
s=s.replace('for cid in ["shufu_f01","nunoya_f01","takigi_m01","sakanaya_m01","chaya_f01","setomono_f01","yakusou_f01","kozo_m01"]:', 'for path in overlay.ASSIGN:\n  var assignment=overlay.ASSIGN[path]\n  var cid=assignment[1]')
s=s.replace('var actor: Node3D\n  for a in snap.actors:\n   if a.model.strip_edges().replace(\'"\',\'\')==cid:\n    actor=pop.get_node(a.node_path)\n    break', 'var actor: Node3D=pop.get_node(path)')
s=s.replace('if not f.ends_with("_grounded.res"): continue','if f!=assignment[2]+"_grounded.res": continue')
s=s.replace('var key=cid+"__"+f.trim_suffix("_grounded.res")','var key=String(actor.name)+"__"+f.trim_suffix("_grounded.res")')
s=s.replace('ap.seek(an.length*phase/8.0,true)','ap.seek(an.length*phase/8.0,true)\n     overlay.update_props()')
s=s.replace('sin(angle)*3.3,1.0,cos(angle)*3.3','sin(angle)*3.3,1.6,cos(angle)*3.3')
s=s.replace('var npc=actor.get_node("NPC")', 'var original_parent=actor.get_parent()\n  var isolated="--isolate" in OS.get_cmdline_user_args()\n  var floor_node: MeshInstance3D\n  if isolated:\n   actor.reparent(root,true)\n   overlay.review_only=path\n   overlay.reparent(root,true)\n   world.visible=false\n   floor_node=MeshInstance3D.new()\n   var plane=PlaneMesh.new()\n   plane.size=Vector2(12,12)\n   floor_node.mesh=plane\n   root.add_child(floor_node)\n   floor_node.global_position=actor.global_position\n  var npc=actor.get_node("NPC")')
s=s.replace('ap.play(old)\n  ap.speed_scale=0.0', 'ap.play(old)\n  ap.speed_scale=0.0\n  if isolated:\n   actor.reparent(original_parent,true)\n   overlay.reparent(world.get_node("Population"),true)\n   world.visible=true\n   floor_node.queue_free()')
s=s.replace('for path in overlay.ASSIGN:\n  var assignment', 'for path in overlay.ASSIGN:\n  if "--cup-only" in OS.get_cmdline_user_args() and not path.ends_with("W3_chaya_f01"): continue\n  var assignment')
(g/'tools/shot_p10_activity_selected.gd').write_text(s)
# R3b vs R3c before contains all original sixteen residents, not an empty village.
s=(g/'tools/shot_village_v2_population.gd').read_text()
s=s.replace('var outdir: String','var outdir: String\nvar activity: Node3D')
s=s.replace('var actors=pop.find_children', 'activity=v.get_node_or_null("Population/ActivityP10")\n if activity==null:\n  activity=Node3D.new()\n  activity.set_script(load("res://scripts/npc_activity_overlay.gd"))\n  v.get_node("Population").add_child(activity)\n for i in 4: await process_frame\n var actors=pop.find_children')
s=s.replace('pop.visible=false','activity.set_enabled(false)\n   for b in actors: b.get_node("NPC").player.speed_scale=0.0')
s=s.replace('pop.visible=true\n   for b in actors:', 'activity.set_enabled(true)\n   for b in actors:')
s=s.replace('var views: Array=', 'if "--baseline-walk" in args: activity.set_enabled(false)\n var views: Array=')
(g/'tools/shot_p10_activity_population.gd').write_text(s)
print('generated capture adapters')
