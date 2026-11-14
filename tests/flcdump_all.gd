extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	DirAccess.make_dir_recursive_absolute("/tmp/claude-0/csflc")
	var names := ["straight1","upInto","up","upOut","downInto","down","downOut","leftInto","left","leftOut","rightInto","right","rightOut","end"]
	for si in names.size():
		var b: PackedByteArray = m.world.fs.get_by_path("flc/%s.flc" % names[si])
		var f := FlcPlayer.open(b)
		for i in f.frame_count:
			f.next_frame(); f.image().save_png("/tmp/claude-0/csflc/%02d_%02d.png" % [si, i])
	quit()
