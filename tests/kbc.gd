extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	for k in ["Keyboard/keyboard", "Keyboard/Keys/q_up", "Keyboard/Keys/one_up", "UI/ProfileCreation/NameField", "UI/PaperDoll/penguin/body"]:
		var d: Dictionary = m.world.sprite(k)
		print("C ", k, " center=", d.get("center"), " canvas=", d.get("canvas"))
	quit()
