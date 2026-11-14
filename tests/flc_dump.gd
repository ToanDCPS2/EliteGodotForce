extends SceneTree
func _init() -> void:
	var w = load("res://epf/game/main.tscn").instantiate(); root.add_child(w)
	await create_timer(0.5).timeout
	var b: PackedByteArray = w.world.loc_bytes("flc/M1C1Intro03NewsPaperFull.flc")
	var f := FlcPlayer.open(b)
	print("frames ", f.frame_count, " speed ", f.speed_ms, " size ", f.width, "x", f.height)
	for i in f.frame_count:
		f.next_frame(); f.image().save_png("/tmp/claude-0/flc/f%02d.png" % i)
	quit()
