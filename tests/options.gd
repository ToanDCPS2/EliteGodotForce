extends SceneTree
func shot(n: String) -> void:
	await create_timer(0.3).timeout
	root.get_texture().get_image().save_png("/tmp/p/op_%s.png" % n)
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._show_menu(); m.menu.show_main(); await shot("main")
	m.menu.show_options(); await shot("options")
	m.menu.show_mic(); await shot("mic")
	m.menu.show_language(); await shot("lang")
	m._set_lang("fr"); await create_timer(0.2).timeout
	m.menu.show_language(); await shot("lang_fr")
	m.menu.show_main(); await shot("main_fr")
	m._set_lang("en")
	quit()
