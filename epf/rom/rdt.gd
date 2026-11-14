class_name EpfRdt
extends RefCounted
## Game.rdt reader (sprite/animation database, a serialized trie keyed by path). Port of tools/epf_rdt.py decode2 + frame_image.
## Frame depth codes: 4 = 4bpp, 8 = 8bpp (index 0 transparent), 3 = A5I3, 5 = A3I5.

var b: PackedByteArray
var keys: Dictionary = {}   # key string -> value record offset

static func parse(bytes: PackedByteArray) -> EpfRdt:
	var r := EpfRdt.new(); r.b = bytes
	r._walk(17, "", {})
	return r

func _walk(off: int, prefix: String, seen: Dictionary) -> void:
	if seen.has(off) or off < 0 or off >= b.size(): return
	seen[off] = true
	var cnt := b[off]; var p := off + 1
	for _i in cnt:
		var ch := b[p]; var nxt := b.decode_u32(p + 1); p += 5
		if ch == 0: keys[prefix] = nxt
		else: _walk(nxt, prefix + char(ch), seen)

## Returns [type, payload] or null. LZ10 payloads are decompressed.
func block(p: int):
	if p < 0 or p >= b.size() - 6: return null
	var t := b.decode_u16(p); var ln := b.decode_u32(p + 2)
	if ln > b.size() or p + 6 + ln > b.size(): return null
	var pl := b.slice(p + 6, p + 6 + ln)
	if pl.size() >= 4 and pl[0] == 0x10:
		var d = EpfCompress.lz10(pl)
		if d != null: pl = d
	return [t, pl]

static func _palette(d: PackedByteArray) -> PackedByteArray:
	var n := (d.size() - 1) / 2
	var out := PackedByteArray(); out.resize(n * 3)
	for i in n:
		var v := d.decode_u16(1 + i * 2)
		var r := v & 31; var g := (v >> 5) & 31; var bl := (v >> 10) & 31
		out[i * 3] = (r << 3) | (r >> 2); out[i * 3 + 1] = (g << 3) | (g >> 2); out[i * 3 + 2] = (bl << 3) | (bl >> 2)
	return out

static func _props(d: PackedByteArray) -> Dictionary:
	var res := {}
	var p := 6
	if d.size() < 8: return res
	var n := d.decode_u16(p); p += 2
	for _i in n:
		if p + 2 > d.size(): break
		var ln := d.decode_u16(p)
		var nm := d.slice(p + 2, p + 2 + ln).get_string_from_ascii()
		var typ := d.decode_u16(p + 2 + ln)
		p += 2 + ln + 2 + 4
		if typ == 3: res[nm] = d[p]; p += 1
		elif typ == 4: res[nm] = [d.decode_s32(p), d.decode_s32(p + 4)]; p += 8
		elif typ == 5: res[nm] = [d.decode_s32(p), d.decode_s32(p + 4), d.decode_s32(p + 8), d.decode_s32(p + 12)]; p += 16
		else: break
	return res

## How long a frame of `ms` really stays up on the DS: the animator adds 16 ms per 60 Hz frame and moves on once the
## total reaches the frame's time, dropping the remainder - so every frame lasts ceil(ms / 16) DS frames
## (100 ms -> 7 frames, 83 -> 6, 50 -> 4, 40 -> 3). Measured in DeSmuME: BaristaCup_talk 6x100 ms loops every 42 frames,
## BluePuffle_TO 6x100 ms lasts 42-43, _readyTO 10x50 ms 40-43, _ready2idle 9x83 ms 54-56.
static func ds_ms(ms: int) -> float:
	return ceilf(float(maxi(ms, 1)) / 16.0) * 1000.0 / 60.0

## Decode one resource. Returns {canvas:[w,h], depth, center, bounds, looping, frames:[{image:Image(canvas size, RGBA8), dur_ms}]} or {} on failure.
func decode(key: String) -> Dictionary:
	if not keys.has(key): return {}
	var off: int = keys[key]
	if b.decode_u16(off) != 3: return {}
	var nent := b.decode_u32(off + 6)
	var p := off + 10
	var entries: Array = []
	for _i in nent:
		var cnt := b.decode_u16(p); p += 2
		var lst: Array = []
		for k in cnt: lst.append(b.decode_u32(p + 4 * k))
		entries.append(lst); p += 4 * cnt
	var out := {"canvas": [0, 0], "depth": 4, "center": null, "bounds": null, "looping": null, "frames": []}
	var pb = block(entries[0][0])
	if pb != null:
		var pr := _props(pb[1])
		for k in pr: out[k] = pr[k]
	var ptrs: Array = entries[1]
	var hb = block(ptrs[0]); if hb == null: return {}
	var hdr: PackedByteArray = hb[1]
	var nframes := hdr.decode_u16(0); var cw := hdr.decode_u16(2); var ch := hdr.decode_u16(4); var depth := hdr[6]
	out["canvas"] = [cw, ch]; out["depth"] = depth
	var tb = block(ptrs[1]); if tb == null: return {}
	var timing: PackedByteArray = tb[1]
	for i in nframes:
		var pal_blk = block(ptrs[2 + 2 * i]); var fr_blk = block(ptrs[3 + 2 * i])
		if pal_blk == null or fr_blk == null: return {}
		var pal := _palette(pal_blk[1])
		var d: PackedByteArray = fr_blk[1]
		var w := d.decode_u16(0); var h := d.decode_u16(2); var fx := d.decode_u16(4); var fy := d.decode_u16(6)
		var dur := timing.decode_u16(i * 2) if timing.size() >= 2 * nframes else 0
		out["frames"].append({"image": _compose(w, h, fx, fy, d, 8, depth, pal, cw, ch), "dur_ms": ds_ms(dur), "rom_ms": dur})
	return out

static func _compose(w: int, h: int, fx: int, fy: int, d: PackedByteArray, data_off: int, depth: int, pal: PackedByteArray, cw: int, ch: int) -> Image:
	var px := PackedByteArray(); px.resize(cw * ch * 4)
	var stride := (w + 1) / 2 if depth == 4 else w
	var npal := pal.size() / 3
	for y in h:
		var dy := fy + y
		if dy >= ch: break
		for x in w:
			var dx := fx + x
			if dx >= cw: break
			var idx := 0; var a := -1
			var pos := data_off + y * stride
			match depth:
				4: idx = (d[pos + x / 2] >> (4 * (x & 1))) & 15
				3:
					var v := d[pos + x]; idx = v & 7; a = (v >> 3) * 255 / 31
				5:
					var v := d[pos + x]; idx = v & 31; a = (v >> 5) * 255 / 7
				_: idx = d[pos + x]
			var o := (dy * cw + dx) * 4
			if idx < npal:
				px[o] = pal[idx * 3]; px[o + 1] = pal[idx * 3 + 1]; px[o + 2] = pal[idx * 3 + 2]
			else:
				px[o] = 255; px[o + 1] = 0; px[o + 2] = 255
			if a < 0: a = 0 if idx == 0 else 255
			px[o + 3] = a
	return Image.create_from_data(cw, ch, false, Image.FORMAT_RGBA8, px)

## Frames side by side (matches the Python exporter's strip layout).
static func strip(dec: Dictionary) -> Image:
	var cw: int = dec["canvas"][0]; var ch: int = dec["canvas"][1]
	var n: int = dec["frames"].size()
	var s := Image.create(cw * n, ch, false, Image.FORMAT_RGBA8)
	for i in n:
		s.blit_rect(dec["frames"][i]["image"], Rect2i(0, 0, cw, ch), Vector2i(i * cw, 0))
	return s
