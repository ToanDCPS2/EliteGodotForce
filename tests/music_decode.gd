extends SceneTree
func _init():
	await process_frame
	var rom := NdsRom.open(OS.get_cmdline_user_args()[0])
	var eng := EpfMusic.open(rom.file("sound/music.bin"), rom.overlay_data(0))
	var t0 := Time.get_ticks_msec()
	eng.preload_all()
	print("decode all ms ", Time.get_ticks_msec() - t0)
	quit()
