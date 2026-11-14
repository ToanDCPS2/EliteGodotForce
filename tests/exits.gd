extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await process_frame; await process_frame
	var n := 0
	for o in m.objs:
		var d: Dictionary = o["data"]
		if d.get("dest") != null: n += 1
	print("objects with dest: ", n, " room now: ", m.room_prefix)
	for o in m.objs:
		var d: Dictionary = o["data"]
		if d.get("dest") != null and str(d["dest"]).to_lower() == "dock0" and o["rt"] == null:
			print("door no-script ->", d["dest"])
	# try every door object once from Town0
	var tried := {}
	for o in m.objs.duplicate():
		var d: Dictionary = o["data"]
		if d.get("dest") == null or tried.has(str(d["dest"])): continue
		tried[str(d["dest"])] = true
		var ok: bool = m._try_exit(d)
		print("door ", d["name"], " dest ", d["dest"], " -> ", ok, " room=", m.room_prefix)
		m.load_room("Town0")
	quit()
