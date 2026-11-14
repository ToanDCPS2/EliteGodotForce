class_name EpfFont
extends RefCounted
## ROM bitmap font (.fnt): u16 glyph count @12, then (u16 code, u16 glyph) pairs from byte 20, then 16-byte glyph records:
##   [0]=x offset [1]=y offset [2]=width [3]=height [4]=advance [5]=line height, u32 pixel offset @12 (absolute).
## Pixels are A5I3 (alpha = value >> 3 of 31), rows padded to a multiple of 8 px. Renders white-with-alpha, tinted by `color`.
var d: PackedByteArray
var pairs := {}
var base := 0
var line_h := 17

static func load_font(fs: EpfArc, path: String) -> EpfFont:
	var b := fs.get_by_path(path)
	if b.size() < 32: return null
	var f := EpfFont.new(); f.d = b
	var n := b.decode_u16(12)
	for i in n: f.pairs[b.decode_u16(20 + i * 4)] = b.decode_u16(22 + i * 4)
	f.base = 20 + n * 4
	f.line_h = b[f.base + 5]
	return f

func _s8(v: int) -> int: return v - 256 if v > 127 else v

func advance(ch: int) -> int:
	var g: int = pairs.get(ch, 0)
	return d[base + g * 16 + 4]

func line_width(s: String) -> int:
	var w := 0
	for i in s.length(): w += advance(s.unicode_at(i))
	return w

func wrap_lines(text: String, max_w: int) -> Array:
	var out: Array = []
	for para in text.split("\n"):
		if max_w <= 0: out.append(para); continue
		var cur := ""
		for word in para.split(" "):
			var t := word if cur == "" else cur + " " + word
			if cur != "" and line_width(t) > max_w: out.append(cur); cur = word
			else: cur = t
		out.append(cur)
	return out

func measure(text: String, wrap_w: int = 0) -> Vector2i:
	var w := 0; var lines: Array = wrap_lines(text, wrap_w)
	for l in lines: w = maxi(w, line_width(l))
	return Vector2i(w, lines.size() * line_h)

## align: 0 left, 1 centre, 2 right
func render(text: String, color: Color = Color.WHITE, wrap_w: int = 0, align: int = 0) -> Image:
	var lines := wrap_lines(text, wrap_w)
	var sz := measure(text, wrap_w)
	var img := Image.create(maxi(sz.x + 2, 1), maxi(sz.y + 2, 1), false, Image.FORMAT_RGBA8)
	var y0 := 0
	for l in lines:
		var lw := line_width(l)
		var x := 0 if align == 0 else ((sz.x - lw) / 2 if align == 1 else sz.x - lw)
		for i in l.length():
			var ch: int = l.unicode_at(i)
			if not pairs.has(ch): x += advance(ch); continue
			var g: int = pairs[ch]; var r := base + g * 16
			var off := d.decode_u32(r + 12)
			var w := d[r + 2]; var h := d[r + 3]
			if off != 0:
				var stride := (w + 7) / 8 * 8
				var gx := x + _s8(d[r]); var gy := y0 + d[r + 1]
				for yy in h:
					for xx in w:
						var v: int = d[off + yy * stride + xx]
						var a := v >> 3
						if a == 0: continue
						var px := gx + xx; var py := gy + yy
						if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height(): continue
						img.set_pixel(px, py, Color(color.r, color.g, color.b, color.a * float(a) / 31.0))
			x += d[r + 4]
		y0 += line_h
	return img

## Text drawn the way the DS HUD draws it: each glyph is its own quad scaled by `sc` and point-sampled
## (source pixel = floor(dest / sc)), placed at its scaled pen position. wrap_w is in output pixels.
func render_scaled(text: String, color: Color, sc: float, wrap_w: int = 0, align: int = 0) -> Image:
	var lines := wrap_lines(text, int(wrap_w / sc) if wrap_w > 0 else 0)
	var mw := 0
	for l in lines: mw = maxi(mw, line_width(l))
	var W := int(ceil(mw * sc)) + 2; var H := int(ceil(lines.size() * line_h * sc)) + 2
	var img := Image.create(maxi(W, 1), maxi(H, 1), false, Image.FORMAT_RGBA8)
	var y0 := 0.0
	for l in lines:
		var lw := line_width(l) * sc
		var x := 0.0 if align == 0 else ((mw * sc - lw) / 2.0 if align == 1 else mw * sc - lw)
		for i in l.length():
			var ch: int = l.unicode_at(i)
			if not pairs.has(ch): x += advance(ch) * sc; continue
			var g: int = pairs[ch]; var r := base + g * 16
			var off := d.decode_u32(r + 12)
			var w := d[r + 2]; var h := d[r + 3]
			if off != 0:
				var stride := (w + 7) / 8 * 8
				var gx := floori(x + _s8(d[r]) * sc); var gy := floori(y0 + d[r + 1] * sc)
				for yy in int(ceil(h * sc)):
					var sy := mini(int(yy / sc), h - 1)
					for xx in int(ceil(w * sc)):
						var sx := mini(int(xx / sc), w - 1)
						var a := d[off + sy * stride + sx] >> 3
						if a == 0: continue
						var px := gx + xx; var py := gy + yy
						if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height(): continue
						img.set_pixel(px, py, Color(color.r, color.g, color.b, color.a * float(a) / 31.0))
			x += d[r + 4] * sc
		y0 += line_h * sc
	return img
