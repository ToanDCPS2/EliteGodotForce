class_name EpfTileset
extends RefCounted
## .tsb: 256 x BGR555 palette (u16 LE, entry 0 = transparent) then N x 64 bytes of 8x8 8bpp tiles.
## .mpb: headerless u16 LE map entries, row-major: bits0-13 tile index, bit14 hflip, bit15 vflip.

var palette: PackedByteArray = PackedByteArray()   # 256*4 RGBA
var tiles: PackedByteArray = PackedByteArray()      # N*64 palette indices
var tile_count := 0

static func load_tsb(bytes: PackedByteArray) -> EpfTileset:
	var t := EpfTileset.new()
	t.palette.resize(256 * 4)
	for i in 256:
		var v := bytes.decode_u16(i * 2)
		var r := v & 31; var g := (v >> 5) & 31; var bl := (v >> 10) & 31
		t.palette[i * 4] = (r << 3) | (r >> 2)
		t.palette[i * 4 + 1] = (g << 3) | (g >> 2)
		t.palette[i * 4 + 2] = (bl << 3) | (bl >> 2)
		t.palette[i * 4 + 3] = 0 if i == 0 else 255
	t.tiles = bytes.slice(512)
	t.tile_count = t.tiles.size() / 64
	return t

## Render a w x h tile map into an RGBA8 Image (palette index 0 transparent).
func render_map(map_bytes: PackedByteArray, w: int, h: int) -> Image:
	var px := PackedByteArray(); px.resize(w * 8 * h * 8 * 4)
	var stride := w * 8 * 4
	for ty in h:
		for tx in w:
			var e := map_bytes.decode_u16((ty * w + tx) * 2)
			var idx := e & 0x3FFF
			var hf := (e & 0x4000) != 0
			var vf := (e & 0x8000) != 0
			if idx >= tile_count: idx = 0
			var tb := idx * 64
			for py in 8:
				var sy := (7 - py) if vf else py
				var dst := ((ty * 8 + py) * w * 8 + tx * 8) * 4
				for pxx in 8:
					var sx := (7 - pxx) if hf else pxx
					var pi := tiles[tb + sy * 8 + sx] * 4
					var d := dst + pxx * 4
					px[d] = palette[pi]; px[d + 1] = palette[pi + 1]; px[d + 2] = palette[pi + 2]; px[d + 3] = palette[pi + 3]
	return Image.create_from_data(w * 8, h * 8, false, Image.FORMAT_RGBA8, px)
