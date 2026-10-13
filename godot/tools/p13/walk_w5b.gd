extends "res://tools/p13/shot_w4.gd"
## One affected-section up/down traversal, no full-village walk or camera changes.
func _run() -> void:
	cl=SA.centerline()
	await _boot()
	var fail:=0
	for dir: String in ["up","down"]:
		var s0:=62.0 if dir=="up" else 91.0
		var s1:=91.0 if dir=="up" else 62.0
		await _tp(s0,dir=="up")
		Input.action_press("move_forward")
		var n:=0
		var lost:=0
		var maxdy:=0.0
		var prev:=player.global_position.y
		var start:=Time.get_ticks_msec()
		while true:
			await physics_frame
			n+=1
			var pp:=player.global_position
			if n%4==1:
				var kc:=clampi(int(round(_s_of(pp)/0.05)),0,cl.size()-1)
				var kt:=clampi(kc+(40 if dir=="up" else -40),0,cl.size()-1)
				var dv:=(cl[kt]-Vector2(pp.x,pp.z)).normalized()
				player.call("snap_yaw",atan2(-dv.x,-dv.y))
				_fix_camera()
			maxdy=maxf(maxdy,absf(pp.y-prev))
			prev=pp.y
			if not player.is_on_floor():
				lost+=1
			var s:=_s_of(pp)
			if (dir=="up" and s>=s1) or (dir=="down" and s<=s1) or Time.get_ticks_msec()-start>45000:
				break
		Input.action_release("move_forward")
		var reached: bool=_s_of(player.global_position)>=s1 if dir=="up" else _s_of(player.global_position)<=s1
		if not reached or lost>0:
			fail+=1
		print("[W5B-WALK] %s reached=%s end_s=%.2f frames=%d lost_floor=%d max_dy=%.4f"%[dir,str(reached),_s_of(player.global_position),n,lost,maxdy])
	print("[W5B-WALK] failures %d"%fail)
	quit(1 if fail else 0)
