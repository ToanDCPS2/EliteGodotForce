extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.8).timeout
	print("OFFS ", JSON.stringify(Array(m.music.eng.song_offs)), " SIZE ", m.music.eng.mb.size())
	quit()
