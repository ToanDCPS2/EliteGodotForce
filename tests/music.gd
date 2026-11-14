extends SceneTree
func _init():
	await process_frame
	var rom := NdsRom.open(OS.get_cmdline_user_args()[0])
	var mb := rom.file("sound/music.bin")
	print("music.bin ", mb.size())
	var eng := EpfMusic.open(mb, rom.overlay_data(0))
	print("insts ", eng.insts.size(), " songs ", eng.song_count())
	var t := eng.room_song_table()
	print("rooms ", t["default"].size(), " TOWN0=", t["default"].get("TOWN0"), " DOJO0=", t["default"].get("DOJO0"), " ATTIC0=", t["default"].get("ATTIC0"))
	eng.start(0)
	var out := PackedVector2Array(); out.resize(512)
	var t0 := Time.get_ticks_msec()
	var carry := 0.0
	var frames := 0
	var peak := 0.0
	while frames < 32768 * 10:
		out.fill(Vector2.ZERO)
		var done := 0
		while done < 512:
			if carry <= 0.0:
				eng.tick(); eng.apply_events(); carry += eng.tick_seconds()
			var n := mini(512 - done, maxi(1, int(ceil(carry * 32768))))
			eng.mix(n, out, done, false)
			done += n; carry -= n / 32768.0
		for v in out: peak = maxf(peak, maxf(absf(v.x), absf(v.y)))
		frames += 512
	print("10s audio mixed in ms: ", Time.get_ticks_msec() - t0, " peak ", peak, " order ", eng.order, " row ", eng.row)
	quit()
