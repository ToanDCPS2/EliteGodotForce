extends SceneTree
## Shoot the M1C1 intro cutscene in the port at several times. args: <out.png> [times...]
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._set_lang("en"); m.set_mission("0.00"); m.load_room("CoffeeShop0")
	await create_timer(0.3).timeout
	m.start_mission(11)
	var shots := []
	var tprev := 0.0
	var args := OS.get_cmdline_user_args()
	for a in args.slice(1):
		await create_timer(float(a) - tprev).timeout; tprev = float(a)
		await process_frame
		var im: Image = root.get_texture().get_image(); im.resize(im.get_width() / 2, im.get_height() / 2); shots.append(im)
		print("t ", a, " cut ", m.cutscene != null, " frame ", m.cutscene.flc.frame_no if m.cutscene else -1, "/", m.cutscene.flc.frame_count if m.cutscene else -1)
	var w: int = shots[0].get_width(); var h: int = shots[0].get_height()
	var sheet := Image.create(w * 3, h * int(ceil(shots.size() / 3.0)), false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var s: Image = shots[i]; s.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(s, Rect2i(0, 0, w, h), Vector2i((i % 3) * w, (i / 3) * h))
	sheet.save_png(args[0]); quit()
