extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	var cs = preload("res://epf/minigames/cart_surfer.gd").new()
	cs.world = m.world
	for c in ["lime", "blue", "red", "black"]:
		cs.color = c
		var base := "Minigames/CartSurfer/CartAnimations/Cart"
		var mp: Dictionary = cs._palette_map(base)
		print("COLOR ", c, " map entries ", mp.size())
	var d: Dictionary = m.world.sprite("Minigames/CartSurfer/CartAnimations/Cart")
	var im: Image = d["frames"][0]["image"]
	var seen := {}
	for y in im.get_height():
		for x in im.get_width():
			var px := im.get_pixel(x, y)
			if px.a > 0.5: seen[px.to_html(false)] = true
	print("CART COLOURS ", seen.keys().size(), " ", seen.keys().slice(0, 16))
	for c in ["lime", "blue"]:
		print("PAL ", c, " ", cs._pal(c).map(func(x): return x.to_html(false)))
	print("SAVE ", m.menu.read_save() if m.menu else "nomenu")
	quit()
