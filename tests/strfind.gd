extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	m._set_lang("en")
	var pats := OS.get_cmdline_user_args()
	for i in 1200:
		var s: String = m.game_text.get_text(i)
		for p in pats:
			if s.to_lower().contains(p.to_lower()): print("STR ", i, " ", p, " len ", s.length())
	quit()
