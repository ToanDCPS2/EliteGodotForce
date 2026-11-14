extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	var args := OS.get_cmdline_user_args()
	m._set_lang("en"); m.room_prefix = args[0]; m.set_mission(args[1])
	await create_timer(0.3).timeout
	for o in m.objs:
		var n := str(o["data"]["name"])
		if n in args.slice(2):
			var d: Dictionary = o["dec"]
			var f0: Dictionary = d["frames"][o["frame"]]
			var img: Image = f0["image"]
			print("OBJ ", n, " xy=", o["data"]["x"], ",", o["data"]["y"], " node=", o["node"].position, " img=", img.get_size(), " used=", img.get_used_rect(), " keys=", f0.keys(), " deckeys=", d.keys())
			for k in d.keys():
				if k != "frames": print("   ", k, "=", str(d[k]).substr(0, 200))
			for k in f0.keys():
				if k != "image": print("   f.", k, "=", f0[k])
	quit()
