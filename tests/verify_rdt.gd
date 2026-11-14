extends SceneTree
## godot --headless --path . -s tests/verify_rdt.gd -- <rom.nds> <out_dir> [max_keys]
## Decodes every sprite natively and compares with the Python-exported PNG strips (RGB compared where alpha > 0).
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var rom := NdsRom.open(a[0]); var out: String = a[1]
	var maxk := int(a[2]) if a.size() > 2 else 1000000
	var rdt := EpfRdt.parse(rom.file("Game.rdt"))
	print("rdt keys: %d" % rdt.keys.size())
	var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out + "/sprites/index.json"))
	var ok := 0; var bad := 0; var fail := 0; var n := 0
	var t0 := Time.get_ticks_msec()
	for k in idx.keys():
		n += 1
		if n > maxk: break
		var dec := rdt.decode(k)
		if dec.is_empty(): fail += 1; continue
		var mine := EpfRdt.strip(dec)
		var ref := Image.load_from_file(out + "/sprites/" + idx[k]["file"])
		if ref == null: fail += 1; continue
		ref.convert(Image.FORMAT_RGBA8)
		var same := mine.get_size() == ref.get_size()
		if same:
			var m := mine.get_data(); var r := ref.get_data()
			for i in range(0, m.size(), 4):
				if m[i + 3] != r[i + 3] or (m[i + 3] > 0 and (m[i] != r[i] or m[i + 1] != r[i + 1] or m[i + 2] != r[i + 2])):
					same = false; break
		if same: ok += 1
		else:
			bad += 1
			if bad < 6: print("  differs: ", k)
	print("sprites identical: %d, differ: %d, failed: %d  (%d ms)" % [ok, bad, fail, Time.get_ticks_msec() - t0])
	quit()
