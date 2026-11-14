extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	print("title: cur=", m.music.cur_song, " ch=", m.music.eng.ch.size())
	m.title.start_pressed.emit(); await create_timer(0.3).timeout
	print("movie: cur=", m.music.cur_song, " ch=", m.music.eng.ch.size(), " voices=", m.music.eng.voices.size(), " cut=", m.cutscene != null)
	quit()
