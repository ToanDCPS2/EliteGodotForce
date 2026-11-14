extends SceneTree
func _init():
	await process_frame
	var rom := NdsRom.open(OS.get_cmdline_user_args()[0])
	var mp := MusicPlayer.new(); root.add_child(mp)
	mp.setup(rom, rom.file("sound/music.bin"))
	mp.play_song(0)
	await create_timer(2.0).timeout
	var t0 := Time.get_ticks_msec()
	print("request switch to 6; cur=", mp.cur_song)
	mp.play_song(6)
	for i in 12:
		await create_timer(0.05).timeout
		print("t+", Time.get_ticks_msec() - t0, " cur=", mp.cur_song, " avail=", mp.pb.get_frames_available())
	quit()
