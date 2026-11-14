extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	for l in ["en", "es", "fr"]:
		m._set_lang(l); m.set_mission("0.00"); m.load_room("Town0"); await create_timer(0.4).timeout
		root.get_texture().get_image().save_png("/tmp/p/town_%s.png" % l)
	m._set_lang("en")
	quit()
