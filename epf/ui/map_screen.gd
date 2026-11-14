extends CanvasLayer
## The island map ("LevelSelect"), opened with the MAP button. Everything here is from the ROM or measured in DeSmuME:
##  - bottom screen: the LevelSelect tile map (728x456) scrolled to the penguin, the 12 places drawn as
##    UI/LevelSelect/level_<name>_up at the positions in overlay 0 (OverlayMeta.scan_map), a glowing pad
##    (level_hotspot_up) at each, and the X button (HUD/MapBack) top right
##  - tap a place: the penguin walks there along the paths between pads (lighthouse -> dock took about 60 frames
##    and the view follows it); places with no path (dojo, mine, iceberg) are reached by a warp
##  - tap the place the penguin stands on: go into that place's room for the current story stage
##  - holding the stylus within about 28 px of an edge scrolls the view that way (here: the mouse pointer at an
##    edge, pressed or not); while the penguin is moving the view stays on it
##  - a mission alert (AddMapAlert type, x, y) shows UI/LevelSelect/icons/<icon> with its tip on (x, y)
##  - top screen: bg/LevelSelect/Map_top with a blinking dot per place (HUD/level_<name>), a flag for each alert
##    and the player's flag on the place the penguin stands on
## Single 16:9 screen: the map fills the view; the top-screen map sits half-size and see-through in the top-left
## corner, in its monitor frame, with the flat grey around the frame cut away.
## Not measured exactly: the walking speed along a path (from one film),
## and the warp (about a second in one film).
signal closed
signal entered(room: String)

const VIEW := Vector2(384, 216)
const SCREEN := VIEW
const SIDE := 0.0
const TOP_ALPHA := 0.7
const MAP_SIZE := Vector2(728, 456)
const EDGE := 28.0
const WALK_SPEED := 1.5            # px per DS frame: lighthouse -> dock (94 px of path) took about 60 frames
const DS_SCREEN := Vector2(256, 192)
# Path waypoints read from DS RAM with the map open (the level defs' neighbour path arrays, 20.12 fixed point
# -> map px). The DS fills them in at run time, so they are not in the ROM image as plain data.
const PATHS := {
	"dock>lighthouse": [144, 345, 111, 337, 86, 317, 79, 292],
	"dock>skiVillage": [144, 345, 133, 291, 143, 222, 171, 182],
	"dock>town": [144, 345, 183, 363, 231, 365, 272, 350],
	"snowFort>iceRink": [432, 304, 413, 330, 377, 330, 355, 307, 345, 273, 343, 237, 350, 202],
	"snowFort>town": [432, 304, 397, 346, 335, 364, 272, 350],
	"snowFort>plaza": [432, 304, 417, 332, 420, 366, 444, 388, 482, 400, 527, 398, 560, 382],
	"skiMountain>skiVillage": [188, 76, 156, 96, 145, 144, 171, 182],
	"lighthouse>dock": [79, 292, 84, 319, 113, 337, 144, 345],
	"lighthouse>skiVillage": [79, 292, 133, 279, 167, 236, 171, 182],
	"town>dock": [272, 350, 237, 367, 186, 366, 144, 345],
	"town>snowFort": [272, 350, 337, 357, 399, 339, 432, 304],
	"iceRink>snowFort": [350, 202, 349, 238, 351, 274, 364, 308, 387, 331, 417, 330, 432, 304],
	"plaza>snowFort": [560, 382, 526, 397, 484, 402, 444, 393, 421, 369, 418, 334, 432, 304],
	"plaza>forest": [560, 382, 608, 402, 659, 390, 668, 346, 650, 299, 617, 257, 574, 238],
	"skiVillage>lighthouse": [172, 184, 164, 240, 129, 281, 79, 292],
	"skiVillage>dock": [172, 184, 140, 223, 126, 284, 144, 345],
	"skiVillage>skiMountain": [171, 182, 142, 146, 154, 96, 188, 76],
	"forest>plaza": [574, 238, 619, 261, 649, 302, 661, 349, 652, 395, 602, 405, 560, 382],
}
const ALERT_ICON := {"STORY_MISSION": "Logo", "FREEPLAY_MISSION": "Logo", "SUPER_ROBOT": "SuperRobot", "ROBOT": "Robot",
	"PUFFLE": "Puffle", "SUSPECT": "Suspect", "DISTRESSED_PENGUIN": "DistressedPenguin"}
const ALERT_FLAG := {"Logo": "Missionflag", "SuperRobot": "SuperRobotflag", "Robot": "Robotflag", "Puffle": "Puffleflag",
	"Suspect": "Suspectflag", "DistressedPenguin": "DistressedPenguinflag"}
const COLORS := ["aqua", "black", "blue", "brown", "darkGreen", "fuschia", "green", "lime", "orange", "peach", "purple",
	"red", "yellow", "pink"]

var world: RomWorld
var sfx
var pads: Dictionary = {}            # level -> Vector2
var links: Dictionary = {}           # level -> [levels]
var rooms: Dictionary = {}           # level -> room prefix for this stage (absent = place closed)
var alerts: Array = []               # [{icon, pos}]
var cur := ""                        # the place the penguin stands on
var color := "blue"

var root := Node2D.new()
var scroll := Node2D.new()
var cam := Vector2.ZERO
var _anims: Array = []               # [{spr, tex, durs, i, t}]
var _pad_rect: Dictionary = {}       # level -> Rect2 in map px
var _pad_art: Dictionary = {}        # level -> {spr, up, down}
var _pen := Sprite2D.new()
var _pen_sets: Dictionary = {}       # name -> {tex, durs, center}
var _pen_set := ""
var _pen_i := 0
var _pen_t := 0.0
var _pen_pos := Vector2.ZERO
var _route: Array = []               # control-point arrays still to walk
var _pt := 1
var _warp_to := ""
var _warp_phase := 0                 # 0 none, 1 going, 2 arriving
var _held := false
var _hover := false                 # the mouse pointer is over the window
var _held_pos := Vector2.ZERO
var _scroll_v := Vector2.ZERO
var _follow := true
var _press_level := ""
var _x_rect := Rect2()
var _busy := false
var _top := Node2D.new()
var _player_flag: Sprite2D
var _dot_pos: Dictionary = {}
var _remap: Dictionary = {}

func setup(w: RomWorld, s, data: Dictionary, stage_rooms: Dictionary, here: String, alert_list: Array, col: String) -> void:
	world = w; sfx = s; pads = data["pads"]; links = data["links"]; rooms = stage_rooms; color = col
	layer = 30
	var back := ColorRect.new(); back.color = Color.BLACK; back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back); add_child(root)
	var clip := Control.new(); clip.clip_contents = true; clip.position = Vector2(SIDE, 0); clip.size = VIEW
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(clip); clip.add_child(scroll)

	var comp: Dictionary = world.compose_layers("LevelSelect")
	if comp.has("image"):
		var bg := Sprite2D.new(); bg.centered = false; bg.texture = ImageTexture.create_from_image(comp["image"])
		scroll.add_child(bg)
	_remap = _palette_map()
	for lv in pads:
		var open: bool = rooms.has(lv)
		var p: Vector2 = pads[lv]
		var up := world.sprite("UI/LevelSelect/level_%s%s_up" % [lv, "" if open else "_disabled"])
		if up.is_empty(): up = world.sprite("UI/LevelSelect/level_%s_up" % lv)
		var art := _add_anim(scroll, up, p)
		var hit := Rect2(p - Vector2(13, 6), Vector2(26, 12))
		if not up.is_empty() and up.get("bounds") != null and open:
			var bd: Array = up["bounds"]; var c: Array = up["center"]
			hit = Rect2(p + Vector2(bd[0] - c[0], bd[1] - c[1]), Vector2(bd[2], bd[3])).grow(2)
		_pad_rect[lv] = hit
		if open:
			var hs := world.sprite("UI/LevelSelect/level_hotspot_up")
			_add_anim(scroll, hs, hit.get_center() + Vector2(0, -1))
			var dn := world.sprite("UI/LevelSelect/level_%s_down" % lv)
			_pad_art[lv] = {"spr": art, "down": dn, "pos": p}
	for a in alert_list:
		var icon: String = ALERT_ICON.get(str(a["type"]), "Logo")
		_add_anim(scroll, world.sprite("UI/LevelSelect/icons/" + icon), a["pos"])
		alerts.append({"icon": icon, "pos": a["pos"], "top": a.get("top", Vector2(-1, -1))})
	for nm in ["penguin", "penguin_Side", "penguin_Up", "penguin_Down", "penguin_SideUp", "penguin_SideDown", "penguin_warp"]:
		var d := world.sprite("UI/LevelSelect/" + nm)
		if d.is_empty(): continue
		var tex: Array = []; var durs: Array = []
		for f in d["frames"]:
			tex.append(ImageTexture.create_from_image(_recolor(f["image"]))); durs.append(maxf(float(f["dur_ms"]), 16.0) / 1000.0)
		var c2 = d.get("center"); if c2 == null: c2 = [0, 0]
		_pen_sets[nm] = {"tex": tex, "durs": durs, "center": Vector2(c2[0], c2[1])}
	_pen.centered = false; scroll.add_child(_pen)
	cur = here if pads.has(here) else (pads.keys()[0] if not pads.is_empty() else "")
	_pen_pos = pads.get(cur, Vector2.ZERO)
	_set_pen("penguin")
	var xb := world.sprite("UI/LevelSelect/HUD/MapBack_up")
	if not xb.is_empty():
		var im: Image = xb["frames"][0]["image"]
		var ur := im.get_used_rect()
		var xs := Sprite2D.new(); xs.centered = false; xs.texture = ImageTexture.create_from_image(im.get_region(ur))
		# DS: 8 px in from the right edge and 5 px down on the 256-wide screen; same margins here
		xs.position = Vector2(SIDE + VIEW.x - (DS_SCREEN.x - ur.position.x), ur.position.y)
		root.add_child(xs); _x_rect = Rect2(xs.position, ur.size).grow(3)
	_build_top()
	get_tree().root.size_changed.connect(_layout)
	_layout(); _center_cam(); _apply()

func _layout() -> void:
	var win := get_tree().root.get_visible_rect().size
	var u := minf(win.x / SCREEN.x, win.y / SCREEN.y)
	root.scale = Vector2(u, u)
	root.position = ((win - SCREEN * u) * 0.5).floor()

func _add_anim(parent: Node, dec: Dictionary, pos: Vector2) -> Sprite2D:
	var spr := Sprite2D.new(); spr.centered = false
	parent.add_child(spr)
	if dec.is_empty() or dec["frames"].is_empty(): return spr
	var c = dec.get("center"); if c == null: c = [0, 0]
	spr.position = pos - Vector2(c[0], c[1])
	var tex: Array = []; var durs: Array = []
	for f in dec["frames"]:
		tex.append(ImageTexture.create_from_image(f["image"])); durs.append(maxf(float(f["dur_ms"]), 16.0) / 1000.0)
	spr.texture = tex[0]
	if tex.size() > 1: _anims.append({"spr": spr, "tex": tex, "durs": durs, "i": 0, "t": 0.0})
	return spr

## palettes/mapPenguin_<colour>.nbfp: the penguin art is drawn with one of them; swap its colours slot by slot
## for the player's colour.
func _pal(c: String) -> Array:
	var b: PackedByteArray = world.fs.get_by_path("palettes/mapPenguin_%s.nbfp" % c)
	var out: Array = []
	for i in b.size() / 2:
		var v := b.decode_u16(i * 2)
		var r := v & 31; var g := (v >> 5) & 31; var bl := (v >> 10) & 31
		out.append(Color8((r << 3) | (r >> 2), (g << 3) | (g >> 2), (bl << 3) | (bl >> 2)))
	return out

func _palette_map() -> Dictionary:
	## Slots 4-7 of a mapPenguin palette are the body, light to dark. The sprites carry their own (green) palette,
	## so their saturated greens, light to dark, are those slots.
	var dst := _pal(color)
	if dst.size() < 8: return {}
	var greens := {}
	for nm in ["penguin", "penguin_Side", "penguin_Up", "penguin_Down", "penguin_SideUp", "penguin_SideDown", "penguin_warp"]:
		var d := world.sprite("UI/LevelSelect/" + nm)
		if d.is_empty(): continue
		for f in d["frames"]:
			var im: Image = f["image"]
			for y in im.get_height():
				for x in im.get_width():
					var px := im.get_pixel(x, y)
					if px.a > 0.5 and px.s > 0.8 and px.g > px.r * 1.5 and px.g > px.b * 1.5: greens[px.to_html(false)] = px.v
	var ks: Array = greens.keys()
	ks.sort_custom(func(x, y): return greens[x] > greens[y])
	var m := {}
	for i in ks.size(): m[ks[i]] = dst[4 + mini(i, 3)]
	return m

func _recolor(im: Image) -> Image:
	if _remap.is_empty(): return im
	var o: Image = im.duplicate(); o.convert(Image.FORMAT_RGBA8)
	for y in o.get_height():
		for x in o.get_width():
			var c := o.get_pixel(x, y)
			if c.a < 0.5: continue
			var k := c.to_html(false)
			if _remap.has(k):
				var n: Color = _remap[k]; n.a = c.a; o.set_pixel(x, y, n)
	return o

## The top-screen monitor, half size in the corner.
func _build_top() -> void:
	_top.scale = Vector2(0.5, 0.5); _top.modulate.a = TOP_ALPHA
	root.add_child(_top)
	var bg := EpfNbfc.load_bg(world, "bg/LevelSelect/Map_top")
	if bg != null:
		bg = _cut_grey(bg)
		var ur := bg.get_used_rect()
		_top.position = Vector2(2, 2) - Vector2(ur.position) * 0.5
		var s := Sprite2D.new(); s.centered = false; s.texture = ImageTexture.create_from_image(bg)
		_top.add_child(s)
	for lv in pads:
		var d := world.sprite("UI/LevelSelect/HUD/level_%s%s" % [lv, "" if rooms.has(lv) else "_disabled"])
		if d.is_empty(): continue
		var sp := _add_anim(_top, d, Vector2.ZERO)
		var bd = d.get("bounds")
		if bd != null: _dot_pos[lv] = Vector2(bd[0], bd[1])
	for a in alerts:
		# AddMapAlert's last two arguments are where the flag's pole stands on the top screen (DeSmuME: the three
		# flags in free play stand at (110,40), (70,70) and (153,135), the values the Dojo/Beach scripts pass)
		var tp: Vector2 = a["top"]
		if tp.x < 0.0:
			var lv := _nearest(a["pos"])
			if lv == "" or not _dot_pos.has(lv): continue
			tp = (_dot_pos[lv] as Vector2) + Vector2(4, 4)
		_add_anim(_top, world.sprite("UI/LevelSelect/HUD/" + str(ALERT_FLAG.get(a["icon"], "Missionflag"))), tp)
	_player_flag = _add_anim(_top, world.sprite("UI/LevelSelect/HUD/playerflag"), Vector2.ZERO)
	_place_player_flag()

## Clears everything outside the monitor frame's black outline (the flat grey and the soft shadow around the
## frame). The outline has small gaps, so it is not a flood fill: a pixel is kept when it lies between the first and
## last dark pixel of its row and of its column (the frame is convex).
func _cut_grey(src: Image) -> Image:
	var im: Image = src.duplicate(); im.convert(Image.FORMAT_RGBA8)
	var w := im.get_width(); var h := im.get_height()
	var l := PackedInt32Array(); var r := PackedInt32Array(); var t := PackedInt32Array(); var b := PackedInt32Array()
	l.resize(h); r.resize(h); t.resize(w); b.resize(w)
	l.fill(w); r.fill(-1); t.fill(h); b.fill(-1)
	for y in h:
		for x in w:
			var c := im.get_pixel(x, y)
			if c.r + c.g + c.b < 0.6:
				if x < l[y]: l[y] = x
				if x > r[y]: r[y] = x
				if y < t[x]: t[x] = y
				if y > b[x]: b[x] = y
	for y in h:
		for x in w:
			if x < l[y] or x > r[y] or y < t[x] or y > b[x]: im.set_pixel(x, y, Color(0, 0, 0, 0))
	return im

func _place_player_flag() -> void:
	if _player_flag == null or not _dot_pos.has(cur): return
	# DeSmuME: standing on the lighthouse (dot at 57,118) the flag's top-left corner is at (58,104)
	_player_flag.position = (_dot_pos[cur] as Vector2) + Vector2(1, -14)

func _nearest(p: Vector2) -> String:
	var best := ""; var bd := 1e9
	for lv in pads:
		var d: float = (pads[lv] as Vector2).distance_to(p)
		if d < bd: bd = d; best = lv
	return best

func _set_pen(nm: String, flip := false) -> void:
	if not _pen_sets.has(nm): nm = "penguin"
	if not _pen_sets.has(nm): return
	if nm != _pen_set: _pen_set = nm; _pen_i = 0; _pen_t = 0.0
	_pen.flip_h = flip

func _center_cam() -> void:
	cam = (_pen_pos - VIEW * 0.5)
	_clamp_cam()

func _clamp_cam() -> void:
	cam.x = clampf(cam.x, 0.0, maxf(MAP_SIZE.x - VIEW.x, 0.0))
	cam.y = clampf(cam.y, 0.0, maxf(MAP_SIZE.y - VIEW.y, 0.0))

## The view's scroll position, snapped to whole screen pixels. Snapping it to whole map pixels made edge scrolling
## judder: at window scale 3-5 one map pixel is several screen pixels, so uneven frame times showed as uneven jumps.
func _cam_px() -> Vector2:
	var u := maxf(root.scale.x, 0.01)
	return (cam * u).round() / u

func _apply() -> void:
	scroll.position = -_cam_px()
	if _pen_sets.has(_pen_set):
		var st: Dictionary = _pen_sets[_pen_set]
		_pen.texture = st["tex"][_pen_i % st["tex"].size()]
		var c: Vector2 = st["center"]
		var wdt: float = _pen.texture.get_width()
		_pen.position = (_pen_pos - Vector2((wdt - c.x) if _pen.flip_h else c.x, c.y)).round()

func _find_route(a: String, b: String) -> Array:
	## shortest chain of open pads joined by paths, or [] when there is none
	var prev := {a: ""}
	var q: Array = [a]
	while not q.is_empty():
		var n: String = q.pop_front()
		if n == b: break
		for m in links.get(n, []):
			if prev.has(m) or not PATHS.has(n + ">" + m): continue
			prev[m] = n; q.append(m)
	if not prev.has(b): return []
	var chain: Array = [b]
	while chain[0] != a: chain.push_front(prev[chain[0]])
	var out: Array = []
	for i in chain.size() - 1: out.append(PATHS["%s>%s" % [chain[i], chain[i + 1]]])
	return out

func _go(lv: String) -> void:
	if _busy or lv == cur or not rooms.has(lv): return
	_route = _find_route(cur, lv)
	_busy = true; _follow = true; _pt = 1
	cur = lv
	if _route.is_empty():
		_warp_to = lv; _warp_phase = 1; _set_pen("penguin_warp")

func _enter() -> void:
	if _busy or not rooms.has(cur): return
	_busy = true
	entered.emit(str(rooms[cur]))

func _process(dt: float) -> void:
	for a in _anims:
		a["t"] += dt
		while a["t"] >= a["durs"][a["i"]]:
			a["t"] -= a["durs"][a["i"]]; a["i"] = (a["i"] + 1) % a["tex"].size()
			(a["spr"] as Sprite2D).texture = a["tex"][a["i"]]
	if _pen_sets.has(_pen_set):
		var st: Dictionary = _pen_sets[_pen_set]
		_pen_t += dt
		while _pen_t >= st["durs"][_pen_i % st["durs"].size()]:
			_pen_t -= st["durs"][_pen_i % st["durs"].size()]
			_pen_i += 1
			if _warp_phase != 0 and _pen_i >= st["tex"].size(): _warp_step()
			_pen_i %= st["tex"].size()
	if not _route.is_empty():
		var left := WALK_SPEED * 60.0 * dt
		var before := _pen_pos
		while left > 0.0 and not _route.is_empty():
			var p: Array = _route[0]
			var tgt := Vector2(p[_pt * 2], p[_pt * 2 + 1])
			var d := _pen_pos.distance_to(tgt)
			if d <= left:
				_pen_pos = tgt; left -= d; _pt += 1
				if _pt * 2 >= p.size(): _route.pop_front(); _pt = 1
			else:
				_pen_pos = _pen_pos.move_toward(tgt, left); left = 0.0
		if _route.is_empty(): _arrive()
		else:
			var v := _pen_pos - before
			if v.length() > 0.01: _face(v)
	# edge scrolling (DS: 4 px a frame at first, about 7 after a few frames; it coasts briefly on release)
	var want := Vector2.ZERO
	# with a mouse the pointer at an edge does what the stylus held at an edge does on the DS
	var inside := _hover and Rect2(Vector2.ZERO, VIEW).has_point(_held_pos)
	if (_held or inside) and not _busy and not _x_rect.grow(6).has_point(_held_pos):
		if _held_pos.x >= VIEW.x - EDGE: want.x = 1
		elif _held_pos.x <= EDGE: want.x = -1
		if _held_pos.y >= VIEW.y - EDGE: want.y = 1
		elif _held_pos.y <= EDGE: want.y = -1
	if want != Vector2.ZERO:
		_follow = false
		var sp := minf(maxf(_scroll_v.length(), 4.0 * 60.0) + 18.0 * 60.0 * dt, 7.0 * 60.0)
		_scroll_v = want.normalized() * sp
	else:
		_scroll_v = _scroll_v.move_toward(Vector2.ZERO, 26.0 * 60.0 * dt)
	if _scroll_v != Vector2.ZERO:
		cam += _scroll_v * dt; _clamp_cam()
	if _follow: _center_cam()
	_apply()

func _face(v: Vector2) -> void:
	var ang := rad_to_deg(v.angle())            # 0 = right, 90 = down
	var left := absf(ang) > 90.0
	var a := absf(ang) if not left else 180.0 - absf(ang)      # 0 = sideways, 90 = straight up/down
	var up := ang < 0.0
	if a > 67.5: _set_pen("penguin_Up" if up else "penguin_Down")
	elif a > 22.5: _set_pen("penguin_SideUp" if up else "penguin_SideDown", left)
	else: _set_pen("penguin_Side", left)

func _arrive() -> void:
	_busy = false; _warp_phase = 0
	_set_pen("penguin")
	_place_player_flag()

func _warp_step() -> void:
	if _warp_phase == 1:
		_pen_pos = pads[_warp_to]; _warp_phase = 2
	else:
		_arrive()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT: _hover = false

func _input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton or e is InputEventMouseMotion or e is InputEventKey): return
	get_viewport().set_input_as_handled()
	if e is InputEventKey:
		if e.pressed and not e.echo and e.keycode == KEY_ESCAPE and not _busy: closed.emit()
		return
	var p: Vector2 = (e.position - root.position) / root.scale.x
	var sp: Vector2 = p                         # whole-screen position (X button)
	p -= Vector2(SIDE, 0)                       # position inside the map area
	if e is InputEventMouseMotion:
		_held_pos = p; _hover = true
		return
	if e.button_index != MOUSE_BUTTON_LEFT: return
	if e.pressed:
		_press_level = ""
		if _x_rect.has_point(sp): _press_level = "<x>"; return
		if p.x < 0.0: return
		_held = true; _held_pos = p
		var mp := p + _cam_px()
		for lv in _pad_rect:
			if rooms.has(lv) and (_pad_rect[lv] as Rect2).grow(3).has_point(mp):
				_press_level = lv
				break
	else:
		_held = false
		if _busy: return
		if _press_level == "<x>" and _x_rect.has_point(sp): closed.emit(); return
		var mp2 := p + _cam_px()
		if _press_level != "" and _pad_rect.has(_press_level) and (_pad_rect[_press_level] as Rect2).grow(3).has_point(mp2):
			if _press_level == cur: _enter()
			else: _go(_press_level)
