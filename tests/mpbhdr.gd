extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	var f := FileAccess.open("/tmp/emu/mpb.txt", FileAccess.WRITE)
	for p in m.world.room_prefixes():
		var b: PackedByteArray = m.world.map_bytes(str(p) + "_map_0.mpb") if m.world.has_method("map_bytes") else PackedByteArray()
		if b.size() == 0: b = m.world.fs.get_by_path("levels/%s_map_0.mpb" % p)
		f.store_line("%s %d %s" % [p, b.size(), b.slice(0, 48).hex_encode()])
	f.close(); quit()
