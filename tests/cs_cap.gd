extends SceneTree
## Port capture for DS comparison: window 256x192 (u=1), Cart Surfer stepped at 60 Hz from the menu.
## args: <frames comma list, in DS frames since the control tap> [keyscript KEY:from:to,...]  (keys: LEFT RIGHT UP DOWN A)
## Saves /tmp/claude-0/cmp/pt_%05d.png
const OFF := 17.0                       # DS frame of ENTER start = port t 0
func _init() -> void:
	root.size = Vector2i(256, 192)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._set_lang("en"); m._show_menu(); await create_timer(0.3).timeout
	m.player_color = "lime"
	var sv: Dictionary = m.menu.read_save(); sv["color"] = "lime"
	var f := FileAccess.open("user://save.json", FileAccess.WRITE); f.store_string(JSON.stringify(sv)); f.close()
	m.menu.start_minigame.emit("cartsurfer", {"mode": "normal", "controls": "pad"})
	var cs = m.minigame
	cs.set_process(false)
	var args := OS.get_cmdline_user_args()
	var want := {}
	for x in args[0].split(","): want[int(x)] = true
	var holds := []
	if args.size() > 1 and args[1] != "":
		for a in args[1].split(","):
			var p := a.split(":"); holds.append([p[0], int(p[1]), int(p[2])])
	var act := {"LEFT": "ui_left", "RIGHT": "ui_right", "UP": "ui_up", "DOWN": "ui_down", "A": "ui_accept"}
	var mx: int = 0
	for k in want: mx = maxi(mx, k)
	# the DS frame index i: the game was started at i = 0, ENTER at i = 17
	for i in mx + 1:
		for h in holds:
			if i == h[1]: Input.action_press(act[h[0]])
			if i == h[2]: Input.action_release(act[h[0]])
		if m.minigame == null: break
		cs._process(1.0 / 60.0)
		if want.has(i):
			await process_frame
			var full: Image = root.get_texture().get_image()
			var im: Image = full.get_region(Rect2i(Vector2i(cs.origin), Vector2i(Vector2(256, 192) * cs.u)))
			im.resize(256, 192, Image.INTERPOLATE_NEAREST)
			im.save_png("/tmp/claude-0/cmp/pt_%05d.png" % i)
			print("CAP ", i, " t ", int(cs.t), " state ", cs.state, " seg ", cs._segment()[0], ":", cs._segment()[1], " lives ", cs.lives, " score ", cs.score)
	quit()
