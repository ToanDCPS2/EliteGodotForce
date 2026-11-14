extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	var ks: Array = []
	for k in m.world.rdt.keys:
		if str(k).begins_with("bg/") or str(k).begins_with("/bg/"): ks.append(k)
	ks.sort()
	print("BGKEYS ", ks)
	quit()
