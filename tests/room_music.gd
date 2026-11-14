extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.3).timeout
	m.title.start_pressed.emit(); await create_timer(0.3).timeout
	m.cutscene._end(); await create_timer(0.3).timeout
	print("menu cur=", m.music.cur_song)
	m._on_start_game(true); await create_timer(0.6).timeout
	print("room=", m.room_prefix, " want song=", m.music.song_for_room(m.room_prefix), " cur=", m.music.cur_song, " ch=", m.music.eng.ch.size(), " voices=", m.music.eng.voices.size(), " avail=", m.music.pb.get_frames_available())
	for r in ["Dojo0", "Beach0", "Attic0"]:
		m.load_room(r); await create_timer(0.4).timeout
		print(r, " cur=", m.music.cur_song, " voices=", m.music.eng.voices.size())
	quit()
