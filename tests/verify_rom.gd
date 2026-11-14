extends SceneTree
## godot --headless --path . -s tests/verify_rom.gd -- <rom.nds> <out_dir>
## Verifies the native ROM reader against the Python extraction (overlays, fs.arc, chunks.arc, names).

func _sha(b: PackedByteArray) -> String:
	var h := HashingContext.new(); h.start(HashingContext.HASH_SHA256); h.update(b); return h.finish().hex_encode()

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var rom := NdsRom.open(a[0]); var out: String = a[1]
	print("game code: %s  files: %d  overlays: %d" % [rom.game_code, rom.files_by_path.size(), rom.overlay_count()])
	# overlays vs out/code/overlays/ov_NNN.bin
	var ok := 0; var bad := 0
	for i in rom.overlay_count():
		var inf := rom.overlay_info(i)
		var mine := rom.overlay_data(i)
		var ref := FileAccess.get_file_as_bytes("%s/code/overlays/ov_%03d.bin" % [out, inf["id"]])
		if mine == ref: ok += 1
		else:
			bad += 1
			if bad < 4: print("  overlay %d mismatch: mine %d bytes, ref %d bytes (compressed=%s)" % [inf["id"], mine.size(), ref.size(), inf["compressed"]])
	print("overlays identical: %d / %d" % [ok, ok + bad])
	# archives
	for nm in ["fs.arc", "chunks.arc"]:
		var arc := EpfArc.parse(rom.file(nm))
		var idx: Array = JSON.parse_string(FileAccess.get_file_as_string("%s/arc/%s_index.json" % [out, nm.get_basename()]))
		var same := 0; var diff := 0
		for e in idx:
			var id: int = ("0x" + str(e["id"])).hex_to_int()
			var mine := arc.get_entry(arc.by_id[id])
			var ref := FileAccess.get_file_as_bytes("%s/arc/%s/%s.%s" % [out, nm.get_basename(), e["id"], e["type"]])
			if mine == ref: same += 1
			else: diff += 1
		print("%s entries identical: %d / %d" % [nm, same, same + diff])
	# name lookups
	var arc := EpfArc.parse(rom.file("fs.arc"))
	var t := arc.get_by_path("tilesets/Town.tsb")
	print("fs.arc tilesets/Town.tsb: %d bytes" % t.size())
	var ch := EpfArc.parse(rom.file("chunks.arc"))
	print("chunk 'system': %d bytes, header ok: %s" % [ch.get_chunk("system").size(), str(ch.get_chunk("system").slice(0, 5) == PackedByteArray([0x1b, 0x4c, 0x75, 0x61, 0x51]))])
	quit()
