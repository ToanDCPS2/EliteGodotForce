extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	for n in ["straight1","upInto","up","upOut","downInto","down","downOut","leftInto","left","leftOut","rightInto","right","rightOut","end"]:
		var b: PackedByteArray = m.world.loc_bytes("flc/%s.flc" % n)
		if b.is_empty(): b = m.world.fs.get_by_path("flc/%s.flc" % n)
		var f := FlcPlayer.open(b) if b.size() > 0 else null
		print("FLC ", n, " bytes ", b.size(), " ", ("frames %d %dx%d speed %d" % [f.frame_count, f.width, f.height, f.speed_ms]) if f else "MISSING")
	for k in ["bg/CartSurfer/CartSurferBottomBG", "bg/CartSurfer/CartSurferBottom_dPad", "palettes/cartsurfer_red.nbfp", "palettes/cartsurfer_lime.nbfp", "palettes/cartsurferhard_red.nbfp"]:
		print("FILE ", k, " ", m.world.fs.get_by_path(k + (".nbfc" if k.begins_with("bg/") else "")).size())
	quit()
