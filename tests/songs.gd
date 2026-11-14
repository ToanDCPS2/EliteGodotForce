extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.8).timeout
	print("DEFAULTS ", m.music.room_defaults)
	print("OVER ", m.music.room_over.keys().slice(0, 30))
	quit()
