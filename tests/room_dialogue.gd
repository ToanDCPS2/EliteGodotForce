extends SceneTree
## godot --headless --path . -s tests/room_dialogue.gd -- rom.nds Prefix
## Fires TOUCHED on every scripted object of a room and prints the resolved dialogue + developer notes.
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var w := RomWorld.open(a[0])
	var chunks := EpfArc.parse(w.rom.file("chunks.arc"))
	var system := chunks.get_chunk("system")
	var en := TextTable.load_id(w.fs, TextTable.EN_DIALOGUE)
	var notes := TextTable.load_id(w.fs, TextTable.DEV_CONTEXT_NOTES)
	var spk := TextTable.load_id(w.fs, TextTable.EN_SPEAKER_LABELS)
	print("english lines: %d, dev notes: %d, speaker labels: %d" % [en.strings.size(), notes.strings.size(), spk.strings.size()])
	var api := GameApi.new()
	var ov := -1
	for r in w.rooms:
		if str(r["map"]).begins_with(a[1] + "_map_"): ov = int(r["overlay"]); break
	var shown := 0
	for o in w.objects.get(ov, w.objects.get(str(ov), [])):
		if o["script"] == null: continue
		var cb := chunks.get_chunk(str(o["script"]).get_file().get_basename())
		if cb.is_empty(): continue
		var rt := ObjectRuntime.create({}, system, cb, api, int(o["id"]), str(o["name"]))
		var before := api.events.size()
		for rs in ["CREATED","TOUCHED","CHANGE_DIALOG"]: rt.fire(api, rs)
		for e in api.events.slice(before):
			if e["fn"] in ["AddDialog", "AddMonologue", "AddConversation"]:
				var tid := int(e["args"][0])
				print("[%s] %s(%s): \"%s\"   {note: %s}" % [o["name"], e["fn"], str(e["args"]), en.get_text(tid), notes.get_text(tid)])
				shown += 1
		if shown > 25: break
	quit()
