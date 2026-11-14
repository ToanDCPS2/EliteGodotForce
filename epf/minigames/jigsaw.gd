class_name JigsawGame
extends CanvasLayer
## The postcard jigsaw (StartMiniGame(_const.JIGSAW = 8, variant)), measured in DeSmuME on the M1C1 map puzzle:
##  - bottom screen bg/Microgames/Jigsaw/Jigsaw_bottom (a dark frame on blue), top screen Jigsaw_top with GameStrings
##    284 "Move and turn the cards so they fit together." (variant table in overlay 0: piece base name, bgs, string)
##  - pieces are 128x128 canvases (Microgames/Jigsaw/<Base><n>_up) turned about their centre; the start layout is
##    fixed (two runs from different frames start identically)
##  - tap a piece: it goes see-through with four yellow handles (Microgames/Jigsaw/rotateHandle) on the corners of an
##    upright box; drag the piece to move it, drag a handle to turn it freely about its centre
##  - the solved map is a 2x2 grid in the frame (pieces 1 TL, 2 TR, 3 BR, 4 BL; matched against UI/Zoom/FinishedMap)
## Start layout and snap targets are read from DS RAM while solving it in DeSmuME (turn each piece upright with
## its handle, drop it near its spot, read where it snaps). On success the DS shows the finished map (UI/Zoom/FinishedMap) with a thought line.
signal finished(ok: bool)

const VIEW := Vector2(384, 216)
const BOARD := Vector2(256, 192)
const BOARD_POS := Vector2(64, 24)                 # the bottom screen at 1:1, under a strip for the instruction
const VARIANTS := [
	{"base": "Microgames/Jigsaw/MapPiece", "count": 4, "text": 284,
	 # start: centre (board px) and turn in degrees (DeSmuME, clockwise-positive like Godot)
	 # start: centre (board px) and turn in degrees, read from DS RAM (piece record x/y in 20.12, angle at x+0x3a8,
	 # 65536 = 360, clockwise like Godot)
	 "start": [[Vector2(224, 50), 225.0], [Vector2(99, 97), 135.0], [Vector2(123, 49), 45.0], [Vector2(33, 156), 180.0]],
	 # target centres: where each piece snapped when dropped upright nearby in DeSmuME
	 "target": [Vector2(97, 65.5), Vector2(163.5, 65.5), Vector2(162.5, 124.5), Vector2(94.5, 121)]},
]
# Measured in DeSmuME on piece 1: an upright piece dropped 10.6 px from its spot snaps, 12.5 px does not.
# Letting go of a turn handle sets the piece to the nearest 45 degrees (9.8 -> 0, 25.3 -> 45, 60.5 -> 45, 99.8 -> 90),
# so a piece only fits when that leaves it upright. A snap plays sound 83; picking up and turning are silent.
const SNAP_DIST := 11.5
const TURN_STEP := 45.0
const SND_SNAP := 83
const HANDLE_HIT := 9.0

var world: RomWorld
var text: TextTable
var sfx
var variant := 0
var pieces: Array = []           # {spr, pos, rot, target, placed, box}
var sel := -1
var drag_mode := ""              # "move" or "turn"
var drag_off := Vector2.ZERO
var turn_from := 0.0
var rot_from := 0.0
var handles: Array = []
var done := false
var _font: EpfFont
var root := Node2D.new()

func _ready() -> void:
	layer = 30                                     # over the room and the HUD (the DS shows neither)
	var back := ColorRect.new(); back.color = Color.BLACK; back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back); move_child(back, 0)
	get_tree().root.size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var win := get_tree().root.get_visible_rect().size
	var u := minf(win.x / VIEW.x, win.y / VIEW.y)
	root.scale = Vector2(u, u)
	root.position = ((win - VIEW * u) * 0.5).floor()

func _input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton or e is InputEventMouseMotion): return
	get_viewport().set_input_as_handled()
	handle_input(e, (e.position - root.position) / root.scale.x)

func setup(w: RomWorld, v: int, t: TextTable, s) -> void:
	world = w; variant = clampi(v, 0, VARIANTS.size() - 1); text = t; sfx = s
	add_child(root)
	var V: Dictionary = VARIANTS[variant]
	var bg := Sprite2D.new(); bg.centered = false; bg.position = BOARD_POS
	var bimg := EpfNbfc.load_bg(world, "bg/Microgames/Jigsaw/Jigsaw_bottom")
	if bimg: bg.texture = ImageTexture.create_from_image(bimg)
	root.add_child(bg)
	# the board's own blue fills the rest of the 16:9 view, so pieces lying over its edge are not on black
	if bimg:
		var edge := ColorRect.new(); edge.color = bimg.get_pixel(1, 1); edge.size = VIEW
		root.add_child(edge); root.move_child(edge, 0)
	var top := ColorRect.new(); top.color = Color8(0, 40, 104); top.size = Vector2(VIEW.x, BOARD_POS.y)
	root.add_child(top)
	_font = EpfFont.load_font(world.fs, "fonts/faceFront.fnt")
	if _font != null and text != null:
		var line := text.get_text(int(V["text"])).replace("%", "").strip_edges()
		var im: Image = _font.render(line, Color.WHITE, int(VIEW.x - 16), 1)
		if im != null:
			var ur := im.get_used_rect()
			var ts := Sprite2D.new(); ts.centered = false; ts.texture = ImageTexture.create_from_image(im.get_region(ur))
			ts.position = Vector2(floorf((VIEW.x - ur.size.x) * 0.5), floorf((BOARD_POS.y - ur.size.y) * 0.5))
			root.add_child(ts)
	for i in int(V["count"]):
		var dec = world.sprite("%s%d_up" % [V["base"], i + 1])
		if dec == null or dec["frames"].is_empty(): continue
		var img: Image = dec["frames"][0]["image"]
		var sp := Sprite2D.new(); sp.texture = ImageTexture.create_from_image(img)
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
		root.add_child(sp)
		var st: Array = V["start"][i]
		pieces.append({"spr": sp, "pos": st[0], "rot": st[1], "target": V["target"][i], "placed": false,
			"box": Rect2(img.get_used_rect())})
	var hd = world.sprite("Microgames/Jigsaw/rotateHandle")
	for k in 4:
		var h := Sprite2D.new(); h.visible = false
		if hd != null and not hd["frames"].is_empty(): h.texture = ImageTexture.create_from_image(hd["frames"][0]["image"])
		root.add_child(h); handles.append(h)
	_draw_all()

func _board(p: Vector2) -> Vector2:
	## a point in this node's space (VIEW px) to board px
	return p - BOARD_POS

func _corners(i: int) -> Array:
	## the upright box of piece i's art, in board px, centred on the piece (DS: the handles do not turn with it)
	var b: Rect2 = pieces[i]["box"]
	var c: Vector2 = pieces[i]["pos"]
	var half := b.size * 0.5
	return [c + Vector2(-half.x, -half.y), c + Vector2(half.x, -half.y), c + Vector2(half.x, half.y), c + Vector2(-half.x, half.y)]

func _draw_all() -> void:
	for i in pieces.size():
		var p: Dictionary = pieces[i]
		var sp: Sprite2D = p["spr"]
		sp.position = BOARD_POS + p["pos"]
		sp.rotation_degrees = p["rot"]
		sp.modulate.a = 0.6 if i == sel else 1.0
	for k in 4:
		var h: Sprite2D = handles[k]
		h.visible = sel >= 0
		if sel >= 0: h.position = BOARD_POS + _corners(sel)[k]

func _hit_piece(bp: Vector2) -> int:
	## topmost unplaced piece whose art covers the point
	for i in range(pieces.size() - 1, -1, -1):
		var p: Dictionary = pieces[i]
		if p["placed"]: continue
		var sp: Sprite2D = p["spr"]
		var local: Vector2 = (bp - p["pos"]).rotated(-deg_to_rad(p["rot"])) + Vector2(64, 64)
		var img: Image = sp.texture.get_image()
		var xi := int(local.x); var yi := int(local.y)
		if xi >= 0 and yi >= 0 and xi < img.get_width() and yi < img.get_height() and img.get_pixel(xi, yi).a > 0.5:
			return i
	return -1

func _raise(i: int) -> int:
	## the touched piece goes on top (drawn last)
	var p: Dictionary = pieces[i]
	pieces.remove_at(i); pieces.append(p)
	root.move_child(p["spr"], handles[0].get_index())
	return pieces.size() - 1

func handle_input(e: InputEvent, pos_view: Vector2) -> void:
	if done: return
	var bp := _board(pos_view)
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			drag_mode = ""
			if sel >= 0:
				var cs := _corners(sel)
				for k in 4:
					if bp.distance_to(cs[k]) <= HANDLE_HIT:
						drag_mode = "turn"
						turn_from = (bp - (pieces[sel]["pos"] as Vector2)).angle()
						rot_from = pieces[sel]["rot"]
						break
			if drag_mode == "":
				var i := _hit_piece(bp)
				if i >= 0:
					sel = _raise(i)
					drag_mode = "move"; drag_off = pieces[sel]["pos"] - bp
				else:
					sel = -1
		else:
			if sel >= 0 and drag_mode != "": _try_snap(sel)
			drag_mode = ""
		_draw_all()
	elif e is InputEventMouseMotion and drag_mode != "" and sel >= 0:
		if drag_mode == "move":
			pieces[sel]["pos"] = (bp + drag_off).clamp(Vector2.ZERO, BOARD)
		else:
			var a: float = (bp - pieces[sel]["pos"]).angle()
			pieces[sel]["rot"] = fposmod(rot_from + rad_to_deg(a - turn_from) + 180.0, 360.0) - 180.0
		_draw_all()

func _try_snap(i: int) -> void:
	var p: Dictionary = pieces[i]
	var ang_off := absf(fposmod(p["rot"] + 180.0, 360.0) - 180.0)
	if (p["pos"] as Vector2).distance_to(p["target"]) <= SNAP_DIST and ang_off < 1.0:
		p["pos"] = p["target"]; p["rot"] = 0.0; p["placed"] = true
		if sfx != null: sfx.play(SND_SNAP)
		sel = -1
		var all := true
		for q in pieces: all = all and q["placed"]
		if all:
			done = true
			_draw_all()
			var tw := create_tween(); tw.tween_interval(1.0)
			tw.tween_callback(func() -> void: finished.emit(true))
