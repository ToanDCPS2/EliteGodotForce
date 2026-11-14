extends SceneTree
## godot --headless --path . -s tests/compose_room.gd -- <out_dir> <RoomPrefix> <event> <result.png>
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var rc := RoomCompose.new(a[0])
	var res := rc.compose(a[1], int(a[2]))
	if res.is_empty(): print("no such room"); quit(1); return
	(res["image"] as Image).save_png(a[3])
	print("%s: placed %d/%d unresolved %s" % [a[1], res["placed"], res["total"], str(res["unresolved"])])
	quit()
