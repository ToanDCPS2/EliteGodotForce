extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	for n in ["DSdigitalHUD", "DSdigital"]:
		var b: PackedByteArray = m.world.fs.get_by_path("fonts/%s.fnt" % n)
		var f := FileAccess.open("/tmp/emu/%s.fnt" % n, FileAccess.WRITE); f.store_buffer(b); f.close()
	quit()
