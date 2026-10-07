extends "res://tools/shot_village_v2_population.gd"
## 隔離的審圖工具反向測試。輸出目錄必須是 scratch；不寫 production scene／NPC library。
var fault_name: String
func _initialize():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--fault="):
   fault_name=arg.trim_prefix("--fault=")
 if fault_name not in ["last-size", "last-save", "after-save", "before-save"]:
  push_error("[CAPTURE_NEGATIVE] Missing or invalid --fault")
  quit(4)
  return
 super._initialize()
func snap(name: String) -> int:
 var inject=(name=="5_walk_through_05" and fault_name in ["last-size","last-save"]) \
  or (name=="1_market_tps_after" and fault_name=="after-save") \
  or (name=="1_market_tps_before" and fault_name=="before-save")
 if inject:
  print("[CAPTURE_NEGATIVE] Inject ",fault_name," at ",name)
  if fault_name=="last-size":
   root.size=Vector2i(1919,1080)
  else:
   # 真正 filesystem error：父路徑是一個檔案，不是資料夾，不能存最後那張 PNG。
   var blocker=outdir+"capture_write_blocker"
   var f=FileAccess.open(blocker,FileAccess.WRITE)
   if f==null:
    push_error("[CAPTURE_NEGATIVE] Cannot create injection blocker")
    return 4
   f.store_line("NOT A DIRECTORY")
   f.close()
   outdir=blocker+"/"
 return await super.snap(name)
