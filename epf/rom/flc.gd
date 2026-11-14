class_name FlcPlayer
extends RefCounted
## Autodesk FLC (FLIC) decoder, 8-bit. Used for the ROM's cutscene movies (Intro.flc etc.).
## Frames are decoded sequentially; call next_frame() to advance and image() to get RGBA.

var data: PackedByteArray
var width := 0
var height := 0
var frame_count := 0
var speed_ms := 58
var pos := 128
var idx: PackedByteArray = PackedByteArray()
var pal: PackedByteArray = PackedByteArray()      # 256 * 3
var frame_no := 0
var _first_pos := 128

static func open(bytes: PackedByteArray) -> FlcPlayer:
	if bytes.size() < 128: return null
	var f := FlcPlayer.new()
	f.data = bytes
	var magic := bytes.decode_u16(4)
	if magic != 0xaf12 and magic != 0xaf11: return null
	f.frame_count = bytes.decode_u16(6)
	f.width = bytes.decode_u16(8); f.height = bytes.decode_u16(10)
	f.speed_ms = maxi(bytes.decode_u32(16) if magic == 0xaf12 else int(bytes.decode_u16(16) * 1000.0 / 70.0), 10)
	f.idx.resize(f.width * f.height)
	f.pal.resize(768)
	f.pos = 128; f._first_pos = 128
	return f

func rewind() -> void:
	pos = _first_pos; frame_no = 0
	idx.fill(0)

func done() -> bool: return frame_no >= frame_count

func next_frame() -> void:
	if pos + 16 > data.size(): return
	var fsize := data.decode_u32(pos)
	var ftype := data.decode_u16(pos + 4)
	var nch := data.decode_u16(pos + 6)
	var q := pos + 16
	if ftype == 0xf1fa:
		for _c in nch:
			var cs := data.decode_u32(q); var ct := data.decode_u16(q + 4)
			_chunk(ct, q + 6, q + cs)
			q += cs
	pos += fsize
	frame_no += 1

func _chunk(t: int, p: int, e: int) -> void:
	match t:
		4, 11: _color(p, 4 if t == 4 else 11)
		7: _delta_flc(p)
		12: _delta_fli(p)
		15: _brun(p)
		16: for i in mini(idx.size(), e - p): idx[i] = data[p + i]
		13: idx.fill(0)

func _color(p: int, t: int) -> void:
	var packets := data.decode_u16(p); p += 2
	var c := 0
	for _k in packets:
		c += data[p]; var n := data[p + 1]; p += 2
		if n == 0: n = 256
		for _i in n:
			for k in 3:
				var v := data[p + k]
				pal[(c & 255) * 3 + k] = v if t == 4 else ((v << 2) | (v >> 4))
			p += 3; c += 1

func _brun(p: int) -> void:
	for y in height:
		p += 1   # packet count byte (ignored; lines are width-delimited)
		var x := 0
		while x < width:
			var n := s8(data[p]); p += 1
			if n < 0:
				n = -n
				for _i in n:
					idx[y * width + x] = data[p]; x += 1; p += 1
			else:
				var v := data[p]; p += 1
				for _i in n:
					idx[y * width + x] = v; x += 1

func _delta_flc(p: int) -> void:
	var lines := data.decode_u16(p); p += 2
	var y := 0
	while lines > 0:
		var w := data.decode_u16(p); p += 2
		var top := (w >> 14) & 3
		if top == 3:
			y += 0x10000 - w   # skip lines (w is negative as s16)
			continue
		if top == 2:
			idx[y * width + width - 1] = w & 0xff
			continue
		# top == 0: packet count
		var x := 0
		for _k in w:
			x += data[p]; var n := s8(data[p + 1]); p += 2
			if n >= 0:
				for _i in n:
					idx[y * width + x] = data[p]; idx[y * width + x + 1] = data[p + 1]
					x += 2; p += 2
			else:
				n = -n
				var a := data[p]; var b := data[p + 1]; p += 2
				for _i in n:
					idx[y * width + x] = a; idx[y * width + x + 1] = b; x += 2
		y += 1; lines -= 1

func _delta_fli(p: int) -> void:
	var y := data.decode_u16(p); var lines := data.decode_u16(p + 2); p += 4
	for _l in lines:
		var pk := data[p]; p += 1
		var x := 0
		for _k in pk:
			x += data[p]; var n := s8(data[p + 1]); p += 2
			if n >= 0:
				for _i in n: idx[y * width + x] = data[p]; x += 1; p += 1
			else:
				n = -n
				var v := data[p]; p += 1
				for _i in n: idx[y * width + x] = v; x += 1
		y += 1

static func s8(v: int) -> int: return v - 256 if v >= 128 else v

func image() -> Image:
	var rgba := PackedByteArray(); rgba.resize(width * height * 4)
	for i in idx.size():
		var c := idx[i] * 3
		rgba[i * 4] = pal[c]; rgba[i * 4 + 1] = pal[c + 1]; rgba[i * 4 + 2] = pal[c + 2]; rgba[i * 4 + 3] = 255
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, rgba)
