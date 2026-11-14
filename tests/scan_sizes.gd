extends SceneTree
func _init() -> void:
	var w := RomWorld.open(OS.get_cmdline_user_args()[0])
	var known := {}
	for id in w.fs.by_id:
		var b := w.fs.get_entry(w.fs.by_id[id])
		if b.size() >= 30000 and b.size() <= 50000 and b.size() % 64 == 0:
			print("S ", id, " ", b.size(), " ", b.slice(0, 8).hex_encode())
	quit()
