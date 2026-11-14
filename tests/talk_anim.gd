extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await process_frame; await process_frame
	for e in m.models3d:
		print(e["name"], " idle=", e["idle"].get("name",""), "/", e["idle"].get("frames",0), " talk=", e["talk"].get("name",""), "/", e["talk"].get("frames",0))
		m.dialog.show_lines("x", ["hi"]); m.talk_target = e["name"]
		await process_frame; await process_frame
		print("  mode while talking:", e["mode"])
		m.dialog.visible = false
		await process_frame; await process_frame
		print("  mode after:", e["mode"])
	quit()
