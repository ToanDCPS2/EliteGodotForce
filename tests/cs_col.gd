extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	for c in ["lime", "blue", "red"]:
		m.player_color = c
		m.start_cart_surfer({})
		await create_timer(0.3).timeout
		var im: Image = m.minigame.cart.texture.get_image()
		var cnt := {}
		for y in im.get_height():
			for x in im.get_width():
				var p := im.get_pixel(x, y)
				if p.a > 0.5: cnt[p.to_html(false)] = cnt.get(p.to_html(false), 0) + 1
		var top := cnt.keys(); top.sort_custom(func(a, b): return cnt[a] > cnt[b])
		print("COL ", c, " ", top.slice(0, 6).map(func(k): return "%s:%d" % [k, cnt[k]]))
		m.minigame._finish(false); await create_timer(3.0).timeout
	quit()
