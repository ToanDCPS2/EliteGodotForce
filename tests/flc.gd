extends SceneTree
func _init():
	await process_frame
	var rom := NdsRom.open(OS.get_cmdline_user_args()[0])
	var fs := EpfArc.parse(rom.file("chunks.arc"))
	var w := RomWorld.open(OS.get_cmdline_user_args()[0])
	var b := w.fs.get_by_path("flc/Intro.flc")
	print("intro bytes ", b.size())
	var f := FlcPlayer.open(b)
	print(f.width, "x", f.height, " frames ", f.frame_count, " speed ", f.speed_ms)
	var t0 := Time.get_ticks_msec()
	for i in f.frame_count:
		f.next_frame()
		if i == 5 or i == 150 or i == 300: f.image().save_png("../previews/intro_%d.png" % i)
	print("decoded in ms ", Time.get_ticks_msec() - t0)
	quit()
