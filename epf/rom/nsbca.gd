class_name EpfNsbca
extends RefCounted
## Nitro BCA0 (.nsbca) joint animation reader. Port of tools/epf_nsbca.py.
## parse(bytes) -> [{name, frames, objs:[{t:[c,c,c], r:c, s:[c,c,c]}]}]; curve c = null | ["c", value] | ["s", start, end, values]

static func _fixs(x: int, int_bits: int, frac_bits: int) -> float:
	var bits := 1 + int_bits + frac_bits
	x &= (1 << bits) - 1
	if (x & (1 << (int_bits + frac_bits))) != 0: x -= 1 << bits
	return float(x) / float(1 << frac_bits)

static func _basis(d: Array) -> Array:
	var inp: Array = [d[4], d[0], d[1], d[2], d[3]]
	var out: Array = [0, 0, 0, 0, 0, 0]
	for i in 5:
		out[i] = inp[i] >> 3
		out[5] = ((out[5] << 3) | (inp[i] & 7)) & 0xFFFF
	var a := Vector3(_fixs(out[1], 0, 12), _fixs(out[2], 0, 12), _fixs(out[3], 0, 12))
	var b := Vector3(_fixs(out[4], 0, 12), _fixs(out[0], 0, 12), _fixs(out[5], 0, 12))
	var c := a.cross(b)
	return [[a.x, a.y, a.z], [b.x, b.y, b.z], [c.x, c.y, c.z]]   # columns

static func parse(b: PackedByteArray) -> Array:
	var res: Array = []
	if b.size() < 16 or b.slice(0, 4).get_string_from_ascii() != "BCA0": return res
	var n := b.decode_u16(14)
	for i in n:
		var o := b.decode_u32(16 + 4 * i)
		if b.slice(o, o + 4).get_string_from_ascii() != "JNT0": continue
		var inf := EpfNsbmd._info(b, o + 8, 4)
		for k in inf["count"]:
			var a := _read_anim(b, o + b.decode_u32(inf["data"] + 4 * k), inf["names"][k])
			if not a.is_empty(): res.append(a)
	return res

static func _curve(b: PackedByteArray, base: int, cur: int, kind: int) -> Array:
	# kind 0 = translation (4/2 byte samples), 1 = scale (8/4 byte stride)
	var info := b.decode_u32(cur); var off := b.decode_u32(cur + 4)
	var st := info & 0xFFFF; var en := (info >> 16) & 0xFFF; var width := (info >> 28) & 3; var rate := (info >> 30) & 3
	var ns := (en - st) >> rate
	var vals: Array = []
	for i in ns:
		if kind == 0: vals.append(_fixs(b.decode_u32(base + off + 4 * i), 19, 12) if width == 0 else _fixs(b.decode_u16(base + off + 2 * i), 3, 12))
		else: vals.append(_fixs(b.decode_u32(base + off + 8 * i), 19, 12) if width == 0 else _fixs(b.decode_u16(base + off + 4 * i), 3, 12))
	return ["s", st, en, vals]

static func _read_anim(b: PackedByteArray, base: int, name: String) -> Dictionary:
	if b.slice(base, base + 4) != PackedByteArray([0x4A, 0, 0x41, 0x43]): return {}
	var nf := b.decode_u16(base + 4); var no := b.decode_u16(base + 6)
	var pivot := base + b.decode_u32(base + 12); var basisd := base + b.decode_u32(base + 16)
	var objs: Array = []
	for oi in no:
		var cur := base + b.decode_u16(base + 20 + 2 * oi)
		var flags := b.decode_u16(cur); cur += 4
		var tr := {"t": [null, null, null], "r": null, "s": [null, null, null]}
		if (flags & 1) != 0: objs.append(tr); continue
		if ((flags >> 1) & 3) == 0:
			for i in 3:
				if ((flags >> (3 + i)) & 1) != 0: tr["t"][i] = ["c", _fixs(b.decode_u32(cur), 19, 12)]; cur += 4
				else: tr["t"][i] = _curve(b, base, cur, 0); cur += 8
		if ((flags >> 6) & 3) == 0:
			if ((flags >> 8) & 1) != 0:
				tr["r"] = ["c", _fetch_mat(b, pivot, basisd, b.decode_u16(cur))]; cur += 4
			else:
				var info := b.decode_u32(cur); var off := b.decode_u32(cur + 4); cur += 8
				var st := info & 0xFFFF; var en := (info >> 16) & 0xFFF; var rate := (info >> 30) & 3
				var vals: Array = []
				for i in (en - st) >> rate: vals.append(_fetch_mat(b, pivot, basisd, b.decode_u16(base + off + 2 * i)))
				tr["r"] = ["s", st, en, vals]
		if ((flags >> 9) & 3) == 0:
			for i in 3:
				if ((flags >> (11 + i)) & 1) != 0: tr["s"][i] = ["c", _fixs(b.decode_u32(cur), 19, 12)]; cur += 8
				else: tr["s"][i] = _curve(b, base, cur, 1); cur += 8
		objs.append(tr)
	return {"name": name, "frames": nf, "objs": objs}

static func _fetch_mat(b: PackedByteArray, pivot: int, basisd: int, x: int) -> Array:
	var idx := x & 0x7FFF
	if (x >> 15) == 1:
		var sn := b.decode_u16(pivot + 6 * idx)
		return EpfNsbmd._pivot(sn & 15, (sn >> 4) & 15, _fixs(b.decode_u16(pivot + 6 * idx + 2), 3, 12), _fixs(b.decode_u16(pivot + 6 * idx + 4), 3, 12))
	var d: Array = []
	for i in 5: d.append(b.decode_u16(basisd + 10 * idx + 2 * i))
	return _basis(d)

static func _sample(c, default, frame: int):
	if c == null: return default
	if c[0] == "c": return c[1]
	var st: int = c[1]; var en: int = c[2]; var vals: Array = c[3]
	if vals.is_empty(): return default
	if frame <= st: return vals[0]
	if frame >= en - 1: return vals[vals.size() - 1]
	var lam := float(frame - st) / float(en - 1 - st)
	var idx := lam * (vals.size() - 1)
	var lo := int(floor(idx)); var hi := int(ceil(idx)); var g := idx - lo
	var a = vals[lo]; var bq = vals[hi]
	if a is Array:   # rotation matrix: component-wise lerp, as the reference does
		var r: Array = []
		for ci in 3: r.append([a[ci][0] * (1 - g) + bq[ci][0] * g, a[ci][1] * (1 - g) + bq[ci][1] * g, a[ci][2] * (1 - g) + bq[ci][2] * g])
		return r
	return a * (1.0 - g) + bq * g

## Per-object matrices for a frame; components with no track fall back to the object's rest value.
static func object_matrices(anim: Dictionary, frame: int, rest: Array) -> Array:
	var out: Array = []
	for i in rest.size():
		if i >= anim["objs"].size(): out.append(rest[i]); continue
		var tr: Dictionary = anim["objs"][i]
		var any := tr["r"] != null or tr["t"][0] != null or tr["t"][1] != null or tr["t"][2] != null or tr["s"][0] != null or tr["s"][1] != null or tr["s"][2] != null
		if not any: out.append(rest[i]); continue
		var rm: Projection = rest[i]
		var sx := Vector3(rm.x.x, rm.x.y, rm.x.z).length(); var sy := Vector3(rm.y.x, rm.y.y, rm.y.z).length(); var sz := Vector3(rm.z.x, rm.z.y, rm.z.z).length()
		if sx == 0.0: sx = 1.0
		if sy == 0.0: sy = 1.0
		if sz == 0.0: sz = 1.0
		var rR: Array = [[rm.x.x / sx, rm.x.y / sx, rm.x.z / sx], [rm.y.x / sy, rm.y.y / sy, rm.y.z / sy], [rm.z.x / sz, rm.z.y / sz, rm.z.z / sz]]
		var t := Vector3(_sample(tr["t"][0], rm.w.x, frame), _sample(tr["t"][1], rm.w.y, frame), _sample(tr["t"][2], rm.w.z, frame))
		var s := Vector3(_sample(tr["s"][0], sx, frame), _sample(tr["s"][1], sy, frame), _sample(tr["s"][2], sz, frame))
		var R: Array = _sample(tr["r"], rR, frame)
		out.append(Projection(Vector4(R[0][0] * s.x, R[0][1] * s.x, R[0][2] * s.x, 0), Vector4(R[1][0] * s.y, R[1][1] * s.y, R[1][2] * s.y, 0), Vector4(R[2][0] * s.z, R[2][1] * s.z, R[2][2] * s.z, 0), Vector4(t.x, t.y, t.z, 1)))
	return out
