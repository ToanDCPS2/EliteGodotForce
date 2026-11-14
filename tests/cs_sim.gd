extends SceneTree
## Step Cart Surfer at 60 Hz without real time. BOT=lean leans through turns. Prints the segment timeline and outcome.
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m.start_cart_surfer({})
	var cs = m.minigame
	cs.set_process(false)
	var bot := OS.get_environment("BOT")
	var held := ""; var last_seg := ""; var segs := []; var runs := []; var lastf := -1; var runlen := 0
	for i in 6000:
		var sg: Array = cs._segment()
		var want := ""
		if bot == "lean" and sg[2] != null and sg[0] != "straight1" and sg[0] != "end":
			want = "ui_left" if sg[2]["type"] == "L" else "ui_right"
		if want != held:
			if held != "": Input.action_release(held)
			if want != "": Input.action_press(want)
			held = want
		if bot == "jump" and sg[0] == "straight1" and i % 120 == 60: Input.action_press("ui_accept")
		if bot == "jump" and i % 120 == 61: Input.action_release("ui_accept")
		if bot == "jump" and i % 120 == 70: Input.action_press("ui_up")
		if bot == "jump" and i % 120 == 72: Input.action_release("ui_up")
		cs._process(1.0 / 60.0)
		if OS.get_environment("SFXLOG") != "": pass
		if sg[0] != last_seg: segs.append("%d:%s" % [int(cs.t), sg[0]]); last_seg = sg[0]
		if i >= 140 and i < 200:
			if sg[1] == lastf: runlen += 1
			else:
				if lastf >= 0: runs.append("%d:%d" % [lastf, runlen])
				lastf = sg[1]; runlen = 1
		if cs.done: break
	print("RUNS ", " ".join(runs))
	print("SEGS ", " ".join(segs.slice(0, 14)))
	print("END t=", int(cs.t), " score ", cs.score, " lives ", cs.lives, " state ", cs.state)
	quit()
