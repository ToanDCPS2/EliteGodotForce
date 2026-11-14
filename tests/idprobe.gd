extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.4).timeout
	var rcb: PackedByteArray = m.chunks.get_chunk("plaza0")
	var rt := ObjectRuntime.create({}, m.system_chunk, rcb, m.api, 0, "plaza0")
	var idt = rt.vm.G.get_v("_id")
	print("_id type: ", typeof(idt), " ", idt)
	if idt != null and idt is LuaVM.LuaTable:
		print("M1C1_DotMailbox2=", idt.get_v("M1C1_DotMailbox2"), " M1C1_DotMailbox=", idt.get_v("M1C1_DotMailbox"))
	quit()
