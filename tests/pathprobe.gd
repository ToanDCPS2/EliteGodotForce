extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	for p in ["english/bg/CartSurfer/CartSurferTitleScreen.nbfc", "bg/CartSurfer/CartSurferTitleScreen_en.nbfc", "bg/CartSurfer/CartSurferTitleScreenEN.nbfc", "bg/english/CartSurferTitleScreen.nbfc", "bg/CartSurfer/english/CartSurferTitleScreen.nbfs", "bg/CartSurfer/CartSurferTitleScreen.nbfs", "bg/CartSurfer/spanish/CartSurferTitleScreen.nbfc", "bg/Menus/english/Title_topscreen2.nbfc", "bg/Menus/Title_topscreen2.nbfc", "bg/JetPack/english/TitleScreen.nbfc", "bg/JetPack/TitleScreen.nbfc"]:
		print("PATH ", p, " ", m.world.fs.get_by_path(p).size())
	quit()
