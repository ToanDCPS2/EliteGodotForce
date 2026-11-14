extends SceneTree
## godot --headless --path . -s tests/verify_nsbmd.gd -- rom.nds
## Parses all 33 models from fs.arc (type-sniffed BMD0) and reports triangle counts / bounds (compare with tools/epf_nsbmd.py: Town robot = 1763 tris, bbox x -79.9..79.3, y 0..155.9, z -72.4..46.0).
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var rom := NdsRom.open(a[0]); var fs := EpfArc.parse(rom.file("fs.arc"))
	var n := 0; var tris_total := 0
	for id in fs.by_id:
		var b := fs.get_entry(fs.by_id[id])
		if b.size() < 16 or b.slice(0, 4).get_string_from_ascii() != "BMD0": continue
		var r := EpfNsbmd.parse(b)
		for m in r["models"]:
			var t := 0; var aabb := AABB(); var first := true
			for d in m["draws"]:
				t += d["verts"].size() / 3
				for v in d["verts"]:
					if first: aabb = AABB(v, Vector3.ZERO); first = false
					else: aabb = aabb.expand(v)
			tris_total += t; n += 1
			print("%08x %s tris=%d tex=%d bbox=%s -> %s" % [id, m["name"], t, r["textures"].size(), aabb.position.snapped(Vector3(0.01,0.01,0.01)), (aabb.position + aabb.size).snapped(Vector3(0.01,0.01,0.01))])
	print("models: %d, triangles: %d" % [n, tris_total])
	quit()
