extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._begin_story(); await create_timer(0.4).timeout
	m.dialog.visible = false
	for o in m.objs:
		if o["data"]["name"] != "BluePuffleBouncy": continue
		for k in 4:
			var b: int = m.api.events.size()
			o["rt"].fire(m.api, "TOUCHED")
			print("count=", m.api.conv_counts, " ev=", m.api.events.slice(b), " err=", o["rt"].error)
			m.api.conv_counts[int(o["data"]["id"])] = k + 2
	quit()
