extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.4).timeout
	m.music.muted = true
	m._begin_story(); await create_timer(0.3).timeout
	print("mission=", m.mission, " room=", m.room_prefix, " objs=", m.objs.size())
	for r in ["Town0","CoffeeShop0","Plaza0","SnowForts0","Dock0","Lighthouse0"]:
		m.load_room(r); await create_timer(0.2).timeout
		var names := []
		for o in m.objs:
			var n: String = o["data"]["name"].get_file()
			if n.begins_with("TinyCoin") or n.begins_with("SnowTinyCoin"): continue
			if not o["node"].visible: names.append("%s#%d(hidden)" % [n, o["data"]["id"]])
		print(r, " ", names)
		var evs := []
		for e in m.dbg_events: evs.append("%s%s" % [e["fn"], str(e["args"])])
		print("   events=", evs)
		print("   unknown=", m.api.unknown_calls, " rt=", m.room_rt != null, " err=", m.room_rt.error if m.room_rt else "")
	quit()
