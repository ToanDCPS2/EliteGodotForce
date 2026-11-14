extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	var pat := OS.get_cmdline_user_args()[0].to_lower()
	for k in m.world.rdt.keys.keys():
		if str(k).to_lower().contains(pat):
			var d: Dictionary = m.world.sprite(str(k))
			print("KEY ", k, " frames ", d.get("frames", []).size(), " ms ", d.get("frames", []).map(func(f): return int(f.get("dur_ms", 0))) if d.has("frames") else "")
	quit()
