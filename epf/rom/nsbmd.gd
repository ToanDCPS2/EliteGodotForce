class_name EpfNsbmd
extends RefCounted
## Nitro BMD0 (.nsbmd) model reader (rest pose). Port of tools/epf_nsbmd.py; format cross-checked against the ISC-licensed 'apicula'.
## parse(bytes) -> {models: [{name, mats:[{name, tex, w, h, diffuse(Color), alpha}], draws:[{mat, verts, uvs, cols}]}], textures: {name: Image}}

static func _u16(b: PackedByteArray, o: int) -> int: return b.decode_u16(o)
static func _u32(b: PackedByteArray, o: int) -> int: return b.decode_u32(o)
static func _fx(v: int, frac: int, bits: int) -> float:
	if v >= (1 << (bits - 1)): v -= (1 << bits)
	return float(v) / float(1 << frac)
static func _fx32(b: PackedByteArray, o: int) -> float: return _fx(_u32(b, o), 12, 32)
static func _fx16(b: PackedByteArray, o: int) -> float: return _fx(_u16(b, o), 12, 16)

## returns {count, data(start offset), dsz, names}
static func _info(b: PackedByteArray, cur: int, dsz_expected: int) -> Dictionary:
	var count := b[cur + 1]
	var p := cur + 4 + 8 + 4 * count
	var dsz := _u16(b, p); p += 4
	var names: Array = []
	var nstart := p + count * dsz
	for i in count: names.append(b.slice(nstart + 16 * i, nstart + 16 * i + 16).get_string_from_ascii())
	return {"count": count, "data": p, "dsz": dsz, "names": names}

static func _mat(cols: Array) -> Projection:
	return Projection(Vector4(cols[0][0], cols[0][1], cols[0][2], 0), Vector4(cols[1][0], cols[1][1], cols[1][2], 0), Vector4(cols[2][0], cols[2][1], cols[2][2], 0), Vector4(cols[3][0], cols[3][1], cols[3][2], 1))

static func _scale(s: float) -> Projection:
	return Projection(Vector4(s, 0, 0, 0), Vector4(0, s, 0, 0), Vector4(0, 0, s, 0), Vector4(0, 0, 0, 1))

static func parse(b: PackedByteArray) -> Dictionary:
	var out := {"models": [], "textures": {}, "palettes": {}, "texinfo": {}}
	if b.size() < 16 or b.slice(0, 4).get_string_from_ascii() not in ["BMD0", "BTX0"]: return out
	var n := _u16(b, 14)
	for i in n:
		var o := _u32(b, 16 + 4 * i)
		var tag := b.slice(o, o + 4).get_string_from_ascii()
		if tag == "MDL0":
			var inf := _info(b, o + 8, 4)
			for k in inf["count"]:
				out["models"].append(_model(b, o + _u32(b, inf["data"] + 4 * k), inf["names"][k]))
		elif tag == "TEX0":
			_tex0(b, o, out)
	# decode textures
	for m in out["models"]:
		for mt in m["mats"]:
			if mt["tex"] != "" and not out["textures"].has(mt["tex"]) and out["texinfo"].has(mt["tex"]):
				var t: Dictionary = out["texinfo"][mt["tex"]]
				var pal = out["palettes"].get(mt["pal"], null)
				out["textures"][mt["tex"]] = _decode_tex(t, pal)
	return out

static func _tex0(b: PackedByteArray, c: int, out: Dictionary) -> void:
	var pal_len := _u16(b, c + 0x30) << 3
	var tex_off := _u16(b, c + 0x0E); var tex_blk := _u32(b, c + 0x14)
	var c1 := _u32(b, c + 0x24); var c2 := _u32(b, c + 0x28)
	var pal_info := _u32(b, c + 0x34); var pal_blk := _u32(b, c + 0x38)
	var pal_block := b.slice(c + pal_blk, c + pal_blk + pal_len)
	var inf := _info(b, c + tex_off, 8)
	for i in inf["count"]:
		var params := _u32(b, inf["data"] + 8 * i)
		var w := 8 << ((params >> 20) & 7); var h := 8 << ((params >> 23) & 7); var fmt := (params >> 26) & 7
		var bpp: int = [0, 8, 2, 4, 8, 2, 8, 16][fmt]
		var ln := w * h * bpp / 8
		var off := (params & 0xFFFF) << 3
		var d1: PackedByteArray; var d2 := PackedByteArray()
		if fmt == 5:
			d1 = b.slice(c + c1 + off, c + c1 + off + ln); d2 = b.slice(c + c2 + off / 2, c + c2 + off / 2 + ln / 2)
		else:
			d1 = b.slice(c + tex_blk + off, c + tex_blk + off + ln)
		out["texinfo"][inf["names"][i]] = {"params": params, "w": w, "h": h, "fmt": fmt, "d1": d1, "d2": d2}
	var pinf := _info(b, c + pal_info, 4)
	for i in pinf["count"]:
		out["palettes"][pinf["names"][i]] = {"off": _u16(b, pinf["data"] + 4 * i) << 3, "block": pal_block}

static func _c5(v: int, a5: int = 31) -> Color:
	var e := func(x: int) -> int: return (x << 3) | (x >> 2)
	return Color8(e.call(v & 31), e.call((v >> 5) & 31), e.call((v >> 10) & 31), e.call(a5))

static func _decode_tex(t: Dictionary, pal) -> Image:
	var w: int = t["w"]; var h: int = t["h"]; var fmt: int = t["fmt"]; var d: PackedByteArray = t["d1"]
	var c0t := ((int(t["params"]) >> 29) & 1) == 1
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var pb: PackedByteArray = pal["block"] if pal != null else PackedByteArray()
	var po: int = pal["off"] if pal != null else 0
	var P := func(i: int) -> int:
		var o: int = po + 2 * i
		return pb.decode_u16(o) if o + 2 <= pb.size() else 0
	match fmt:
		1:
			for n in w * h:
				var x := d[n]; var a3 := x >> 5
				img.set_pixel(n % w, n / w, _c5(P.call(x & 31), (a3 << 2) | (a3 >> 1)))
		2, 3:
			var per := 4 if fmt == 2 else 2; var bits := 8 / per
			for n in w * h:
				var x := (d[n / per] >> (bits * (n % per))) & ((1 << bits) - 1)
				img.set_pixel(n % w, n / w, _c5(P.call(x), 0 if (x == 0 and c0t) else 31))
		4:
			for n in w * h:
				var x := d[n]; img.set_pixel(n % w, n / w, _c5(P.call(x), 0 if (x == 0 and c0t) else 31))
		5:
			var d2: PackedByteArray = t["d2"]; var bx := w / 4
			for y in h:
				for x in w:
					var bi := bx * (y / 4) + x / 4
					var blk := d.decode_u32(4 * bi); var ex := d2.decode_u16(2 * bi)
					var tx := (blk >> (2 * (4 * (y % 4) + x % 4))) & 3
					var mode := ex >> 14; var pa := (ex & 0x3FFF) << 1
					var col := func(k: int) -> Color:
						var o: int = po + pa + 2 * k
						return _c5(pb.decode_u16(o) if o + 2 <= pb.size() else 0)
					var px := Color(0, 0, 0, 0)
					match mode:
						0: px = col.call(tx) if tx < 3 else Color(0, 0, 0, 0)
						1:
							if tx == 0: px = col.call(0)
							elif tx == 1: px = col.call(1)
							elif tx == 2: px = (col.call(0) as Color).lerp(col.call(1), 0.5)
						2: px = col.call(tx)
						_:
							if tx == 0: px = col.call(0)
							elif tx == 1: px = col.call(1)
							elif tx == 2: px = (col.call(1) as Color) * 0.375 + (col.call(0) as Color) * 0.625
							else: px = (col.call(0) as Color) * 0.375 + (col.call(1) as Color) * 0.625
					img.set_pixel(x, y, px)
		6:
			for n in w * h:
				var x := d[n]; img.set_pixel(n % w, n / w, _c5(P.call(x & 7), x >> 3))
		7:
			for n in w * h:
				var v := d.decode_u16(2 * n); img.set_pixel(n % w, n / w, _c5(v, 31 if (v >> 15) == 1 else 0))
	return img

static func _object(b: PackedByteArray, p0: int) -> Projection:
	var p := p0
	var flags := _u16(b, p); p += 2
	var t := flags & 1; var r := (flags >> 1) & 1; var s := (flags >> 2) & 1; var pv := (flags >> 3) & 1
	var m0 := _u16(b, p); p += 2
	var T := Vector3.ZERO; var S := Vector3.ONE
	var R: Array = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]   # columns
	if t == 0: T = Vector3(_fx32(b, p), _fx32(b, p + 4), _fx32(b, p + 8)); p += 12
	if pv == 1:
		var a := _fx16(b, p); var bb := _fx16(b, p + 2); p += 4
		R = _pivot((flags >> 4) & 15, (flags >> 8) & 15, a, bb)
	elif r == 0:
		var v: Array = [_fx(m0, 12, 16)]
		for i in 8: v.append(_fx16(b, p + 2 * i))
		p += 16
		R = [[v[0], v[1], v[2]], [v[3], v[4], v[5]], [v[6], v[7], v[8]]]
	if s == 0: S = Vector3(_fx32(b, p), _fx32(b, p + 4), _fx32(b, p + 8)); p += 12
	return _mat([[R[0][0] * S.x, R[0][1] * S.x, R[0][2] * S.x], [R[1][0] * S.y, R[1][1] * S.y, R[1][2] * S.y], [R[2][0] * S.z, R[2][1] * S.z, R[2][2] * S.z], [T.x, T.y, T.z]])

static func _pivot(select: int, neg: int, a: float, bb: float) -> Array:
	if select >= 9: return [[-a, 0, 0], [0, 0, 0], [0, 0, 0]]
	var o := 1.0 if (neg & 1) == 0 else -1.0
	var c := bb if (neg & 2) == 0 else -bb
	var d := a if (neg & 4) == 0 else -a
	var z := 0.0
	var v: Array
	match select:
		0: v = [o, z, z, z, a, bb, z, c, d]
		1: v = [z, o, z, a, z, bb, c, z, d]
		2: v = [z, z, o, a, bb, z, c, d, z]
		3: v = [z, a, bb, o, z, z, z, c, d]
		4: v = [a, z, bb, z, o, z, c, z, d]
		5: v = [a, bb, z, z, z, o, c, d, z]
		6: v = [z, a, bb, z, c, d, o, z, z]
		7: v = [a, z, bb, c, z, d, z, o, z]
		_: v = [a, bb, z, c, d, z, z, z, o]
	return [[v[0], v[1], v[2]], [v[3], v[4], v[5]], [v[6], v[7], v[8]]]

static func _model(b: PackedByteArray, c: int, name: String) -> Dictionary:
	var rc := _u32(b, c + 4); var mo := _u32(b, c + 8); var po := _u32(b, c + 12); var io := _u32(b, c + 16)
	var nobj := b[c + 23]
	var up := _fx32(b, c + 28); var down := _fx32(b, c + 32)
	var oi := _info(b, c + 0x40, 4)
	var objects: Array = []
	for i in oi["count"]: objects.append(_object(b, c + 0x40 + _u32(b, oi["data"] + 4 * i)))
	var mc := c + mo
	var texpair := _u16(b, mc); var palpair := _u16(b, mc + 2)
	var mi := _info(b, mc + 4, 4)
	var mats: Array = []
	for i in mi["count"]:
		var q := mc + _u32(b, mi["data"] + 4 * i)
		var dif := _u32(b, q + 4)
		mats.append({"name": mi["names"][i], "tex": "", "pal": "", "w": _u16(b, q + 32), "h": _u16(b, q + 34),
			"diffuse": Color((dif & 31) / 31.0, ((dif >> 5) & 31) / 31.0, ((dif >> 10) & 31) / 31.0), "vtxcol": ((dif >> 15) & 1) == 1,
			"alpha": float((_u32(b, q + 12) >> 16) & 31) / 31.0})
	for pass_i in 2:
		var key := "tex" if pass_i == 0 else "pal"
		var inf := _info(b, mc + (texpair if pass_i == 0 else palpair), 4)
		for k in inf["count"]:
			var o2 := _u16(b, inf["data"] + 4 * k); var num := b[inf["data"] + 4 * k + 2]
			for j in num: mats[b[mc + o2 + j]][key] = inf["names"][k]
	var pieces: Array = []
	var pi := _info(b, c + po, 4)
	for i in pi["count"]:
		var q := c + po + _u32(b, pi["data"] + 4 * i)
		var co := _u32(b, q + 8); var cl := _u32(b, q + 12)
		pieces.append(b.slice(q + co, q + co + cl))
	var inv: Array = []
	var q2 := c + io
	for i in nobj:
		if q2 + 84 > b.size(): break
		var v: Array = []
		for k in 12: v.append(_fx32(b, q2 + 4 * k))
		inv.append(_mat([[v[0], v[1], v[2]], [v[3], v[4], v[5]], [v[6], v[7], v[8]], [v[9], v[10], v[11]]]))
		q2 += 84
	# render commands (kept so the pose can be rebuilt per animation frame)
	var plen := {0: 0, 1: 0, 2: 2, 3: 1, 4: 1, 5: 1, 6: 3, 7: 1, 8: 1, 0xb: 0, 0xc: 2, 0xd: 2, 0x24: 1, 0x26: 4, 0x2b: 0, 0x40: 0, 0x44: 1, 0x46: 4, 0x47: 2, 0x66: 5, 0x80: 0}
	var ops: Array = []
	var q3 := c + rc
	while q3 < b.size():
		var op := b[q3]; q3 += 1
		var par: Array = []
		if op == 9:
			var cnt := b[q3 + 1]
			for i in 2 + 3 * cnt: par.append(b[q3 + i])
			q3 += 2 + 3 * cnt
		else:
			if not plen.has(op): break
			for i in plen[op]: par.append(b[q3 + i])
			q3 += plen[op]
		if op == 1: break
		ops.append([op, par])
	var model := {"name": name, "mats": mats, "pieces": pieces, "inv": inv, "ops": ops, "objects": objects, "up": up, "down": down}
	model["draws"] = build_draws(model, objects)
	return model

## Execute the render commands with the given per-object matrices (rest pose = model["objects"]).
static func build_draws(model: Dictionary, objects: Array) -> Array:
	var stack: Array = []
	for i in 32: stack.append(Projection.IDENTITY)
	var cur := Projection.IDENTITY
	var curmat := 0
	var draws: Array = []
	var mats: Array = model["mats"]; var pieces: Array = model["pieces"]; var inv: Array = model["inv"]
	for e in model["ops"]:
		var op: int = e[0]; var par: Array = e[1]
		match op:
			3: cur = stack[par[0]]
			4, 0x24, 0x44: curmat = par[0]
			5: draws.append(_draw(pieces[par[0]], cur, stack, mats[curmat], curmat))
			6, 0x26, 0x46, 0x66:
				var sp := -1; var lp := -1
				if op == 0x26 or op == 0x66: sp = par[3]
				if op == 0x66: lp = par[4]
				elif op == 0x46: lp = par[3]
				if lp >= 0: cur = stack[lp]
				cur = cur * objects[par[0]]
				if sp >= 0: stack[sp] = cur
			9:
				var acc := Projection(Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO)
				for k in par[1]:
					var sp2: int = par[2 + 3 * k]; var ib: int = par[3 + 3 * k]; var wt: float = par[4 + 3 * k] / 256.0
					var ibm: Projection = inv[ib] if ib < inv.size() else Projection.IDENTITY
					var m: Projection = stack[sp2] * ibm
					acc = Projection(acc.x + m.x * wt, acc.y + m.y * wt, acc.z + m.z * wt, acc.w + m.w * wt)
				cur = acc; stack[par[0]] = cur
			0xb: cur = cur * _scale(model["up"])
			0x2b: cur = cur * _scale(model["down"])
	return draws

class GpuState:
	var cm: Projection
	var vtx := Vector3.ZERO
	var uv := Vector2.ZERO
	var col := Color(1, 1, 1)
	var prim := 0
	var start := 0
	var verts: Array = []
	var P := PackedVector3Array()
	var U := PackedVector2Array()
	var C := PackedColorArray()
	func push() -> void:
		var r: Vector4 = cm * Vector4(vtx.x, vtx.y, vtx.z, 1.0)
		verts.append([Vector3(r.x, r.y, r.z), uv, col])
	func emit(k: int) -> void:
		var a: Array = verts[k]
		P.append(a[0]); U.append(a[1]); C.append(a[2])
	func end_prim() -> void:
		var end := verts.size(); var i := start
		if prim == 0:
			while i + 2 < end:
				emit(i); emit(i + 1); emit(i + 2); i += 3
		elif prim == 1:
			while i + 3 < end:
				for k in [0, 1, 2, 0, 2, 3]: emit(i + k)
				i += 4
		elif prim == 2:
			var odd := false
			while i + 2 < end:
				if not odd: emit(i); emit(i + 1); emit(i + 2)
				else: emit(i); emit(i + 2); emit(i + 1)
				i += 1; odd = not odd
		else:
			while i + 3 < end:
				for k in [0, 1, 3, 0, 3, 2]: emit(i + k)
				i += 2
		start = verts.size()

static func _draw(cmds: PackedByteArray, cur0: Projection, stack: Array, mat: Dictionary, mi: int) -> Dictionary:
	var sizes := {0: 0, 0x14: 1, 0x15: 0, 0x16: 16, 0x17: 12, 0x18: 16, 0x19: 12, 0x1a: 9, 0x1b: 3, 0x1c: 3, 0x20: 1, 0x21: 1, 0x22: 1, 0x23: 2, 0x24: 1, 0x25: 1, 0x26: 1, 0x27: 1, 0x28: 1, 0x29: 1, 0x2a: 1, 0x2b: 1, 0x30: 1, 0x31: 1, 0x32: 1, 0x33: 1, 0x34: 32, 0x40: 1, 0x41: 0, 0x50: 1, 0x60: 1, 0x70: 3, 0x71: 2, 0x72: 1}
	var g := GpuState.new()
	g.cm = cur0
	var tw := float(maxi(int(mat["w"]), 1)); var th := float(maxi(int(mat["h"]), 1))
	if mat["vtxcol"] and mat["diffuse"] != Color(1, 1, 1): g.col = mat["diffuse"]
	var pos := 0; var n := cmds.size()
	while pos + 4 <= n:
		var ops := cmds.slice(pos, pos + 4); pos += 4
		for op in ops:
			if not sizes.has(op): return _pack(g.P, g.U, g.C, mi)
			var npar: int = sizes[op]
			var par: Array = []
			for i in npar: par.append(cmds.decode_u32(pos + 4 * i))
			pos += 4 * npar
			match op:
				0x14: g.cm = stack[par[0] & 31]
				0x1b: g.cm = g.cm * Projection(Vector4(_fx(par[0], 12, 32), 0, 0, 0), Vector4(0, _fx(par[1], 12, 32), 0, 0), Vector4(0, 0, _fx(par[2], 12, 32), 0), Vector4(0, 0, 0, 1))
				0x40: g.end_prim(); g.prim = par[0] & 3; g.start = g.verts.size()
				0x41: g.end_prim()
				0x23:
					g.vtx = Vector3(_fx(par[0] & 0xFFFF, 12, 16), _fx(par[0] >> 16, 12, 16), _fx(par[1] & 0xFFFF, 12, 16)); g.push()
				0x24:
					var p: int = par[0]
					g.vtx = Vector3(_fx(p & 0x3FF, 6, 10), _fx((p >> 10) & 0x3FF, 6, 10), _fx((p >> 20) & 0x3FF, 6, 10)); g.push()
				0x25, 0x26, 0x27:
					var p2: int = par[0]; var a := _fx(p2 & 0xFFFF, 12, 16); var bq := _fx(p2 >> 16, 12, 16)
					if op == 0x25: g.vtx = Vector3(a, bq, g.vtx.z)
					elif op == 0x26: g.vtx = Vector3(a, g.vtx.y, bq)
					else: g.vtx = Vector3(g.vtx.x, a, bq)
					g.push()
				0x28:
					var p3: int = par[0]
					g.vtx += Vector3(_fx(p3 & 0x3FF, 9, 10), _fx((p3 >> 10) & 0x3FF, 9, 10), _fx((p3 >> 20) & 0x3FF, 9, 10)) / 8.0
					g.push()
				0x22:
					var s := _fx(par[0] & 0xFFFF, 4, 16); var t := _fx(par[0] >> 16, 4, 16)
					g.uv = Vector2(s / tw, 1.0 - t / th)
				0x20:
					var pc: int = par[0]; g.col = Color((pc & 31) / 31.0, ((pc >> 5) & 31) / 31.0, ((pc >> 10) & 31) / 31.0)
				0x21: g.col = Color(1, 1, 1)
	return _pack(g.P, g.U, g.C, mi)

static func _pack(P, U, C, mi: int) -> Dictionary:
	return {"mat": mi, "verts": P, "uvs": U, "cols": C}

## Build a MeshInstance3D-ready ArrayMesh with one surface per draw; returns {mesh, aabb}
static func to_mesh(model: Dictionary, textures: Dictionary) -> Dictionary:
	var mesh := ArrayMesh.new()
	for d in model["draws"]:
		if d["verts"].size() == 0: continue
		var arr := []; arr.resize(Mesh.ARRAY_MAX)
		# DS winding is CCW front; Godot too. Flip Z handedness is handled by caller if needed.
		arr[Mesh.ARRAY_VERTEX] = d["verts"]; arr[Mesh.ARRAY_TEX_UV] = d["uvs"]; arr[Mesh.ARRAY_COLOR] = d["cols"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var m: Dictionary = model["mats"][d["mat"]]
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.vertex_color_use_as_albedo = true
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		sm.alpha_scissor_threshold = 0.5
		if m["tex"] != "" and textures.has(m["tex"]):
			sm.albedo_texture = ImageTexture.create_from_image(textures[m["tex"]])
			sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		else:
			sm.albedo_color = m["diffuse"]
		mesh.surface_set_material(mesh.get_surface_count() - 1, sm)
	return {"mesh": mesh, "aabb": mesh.get_aabb()}
