class_name EpfNbfc
extends RefCounted
## DS background triple: .nbfc (8bpp tiles) + .nbfp (BGR555 palette) + .nbfs (32x24 text-BG screen entries) -> 256x192 Image.
static func load_bg(w, base: String) -> Image:
	var tiles = w.loc_bytes(base + ".nbfc")
	var pal = w.loc_bytes(base + ".nbfp")
	var scr = w.loc_bytes(base + ".nbfs")
	# localised variants (CartSurferTitleScreen_en) carry only their own tiles: palette and map come from the base
	var plain := base.trim_suffix("_en").trim_suffix("_es").trim_suffix("_sp")
	if (pal == null or pal.size() == 0) and plain != base: pal = w.loc_bytes(plain + ".nbfp")
	if (scr == null or scr.size() == 0) and plain != base: scr = w.loc_bytes(plain + ".nbfs")
	if tiles == null or pal == null or scr == null or tiles.size() == 0 or pal.size() < 2 or scr.size() < 1536: return null
	var cols: Array[Color] = []
	for i in 256:
		var v: int = pal.decode_u16(i * 2) if i * 2 + 1 < pal.size() else 0
		cols.append(Color(float(v & 31) / 31.0, float((v >> 5) & 31) / 31.0, float((v >> 10) & 31) / 31.0, 1.0))
	var img := Image.create(256, 192, false, Image.FORMAT_RGBA8)
	var ntiles: int = tiles.size() / 64
	for ty in 24:
		for tx in 32:
			var e: int = scr.decode_u16((ty * 32 + tx) * 2)
			var ti := e & 0x3FF; var hf := (e >> 10) & 1; var vf := (e >> 11) & 1
			if ti >= ntiles: continue
			for py in 8:
				for px in 8:
					var sx := 7 - px if hf == 1 else px
					var sy := 7 - py if vf == 1 else py
					var idx: int = tiles[ti * 64 + sy * 8 + sx]
					img.set_pixel(tx * 8 + px, ty * 8 + py, cols[idx])
	return img
