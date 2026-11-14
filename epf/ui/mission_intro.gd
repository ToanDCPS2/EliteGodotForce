extends CanvasLayer
## The briefing shown when a mission is accepted (DeSmuME, Dot in the Dojo -> "I want to join the EPF"):
##  - top screen bg/Cutscenes/MissionIntroTop (the EPF badge), bottom screen bg/Cutscenes/MissionIntroBottom
##  - bottom, in fonts/DSdigital: "MISSION n:" and the mission's name in yellow (y 38 and 52), then its
##    description in green typed out one letter about every 5 frames (two lines from y 85)
##  - when the text is complete the START MISSION button (GameStrings 255) appears at (66,149)-(191,171);
##    tapping it starts the mission
## Single 16:9 screen: the bottom screen at 1:1 on the right, the top screen at half size to its left.
signal start_pressed

const VIEW := Vector2(384, 216)
const BOT := Vector2(128, 12)
const TOP_POS := Vector2(0, 60)
const YELLOW := Color8(255, 255, 0)
const GREEN := Color8(0, 255, 0)
const CHAR_FRAMES := 5.0
const BTN := Rect2(66, 149, 126, 23)

var world: RomWorld
var root := Node2D.new()
var _font: EpfFont
var _desc := ""
var _shown := 0
var _t := 0.0
var _desc_spr := Sprite2D.new()
var _btn := Node2D.new()
var _pressed := false
var _done := false

func setup(w: RomWorld, head: String, title: String, desc: String, start_text: String) -> void:
	world = w; layer = 30
	var back := ColorRect.new(); back.color = Color.BLACK; back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back); add_child(root)
	var top := EpfNbfc.load_bg(world, "bg/Cutscenes/MissionIntroTop")
	if top != null:
		var ts := Sprite2D.new(); ts.centered = false; ts.texture = ImageTexture.create_from_image(top)
		ts.scale = Vector2(0.5, 0.5); ts.position = TOP_POS; root.add_child(ts)
	var bot := EpfNbfc.load_bg(world, "bg/Cutscenes/MissionIntroBottom")
	if bot != null:
		var bs := Sprite2D.new(); bs.centered = false; bs.texture = ImageTexture.create_from_image(bot)
		bs.position = BOT; root.add_child(bs)
	_font = EpfFont.load_font(world.fs, "fonts/DSdigital.fnt")
	_line(head.to_upper(), YELLOW, 38.0)
	_line(title.to_upper(), YELLOW, 52.0)
	_desc = desc.strip_edges().to_upper()
	_desc_spr.centered = false; root.add_child(_desc_spr)
	# the button: a white outline with a darker one inside, as drawn on the DS
	var o := ColorRect.new(); o.color = Color8(214, 222, 214); o.position = BOT + BTN.position; o.size = BTN.size
	var i := ColorRect.new(); i.color = Color8(0, 82, 41); i.position = BOT + BTN.position + Vector2(2, 2); i.size = BTN.size - Vector2(4, 4)
	_btn.add_child(o); _btn.add_child(i)
	if _font != null:
		var im: Image = _font.render(start_text.to_upper(), YELLOW)
		var ur := im.get_used_rect()
		if ur.size.x > 0:
			var s := Sprite2D.new(); s.centered = false; s.texture = ImageTexture.create_from_image(im.get_region(ur))
			s.position = (BOT + BTN.get_center() - Vector2(ur.size) * 0.5).floor()
			_btn.add_child(s)
	_btn.visible = false; root.add_child(_btn)
	get_tree().root.size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var win := get_tree().root.get_visible_rect().size
	var u := minf(win.x / VIEW.x, win.y / VIEW.y)
	root.scale = Vector2(u, u)
	root.position = ((win - VIEW * u) * 0.5).floor()

func _line(t: String, col: Color, y: float) -> void:
	if _font == null: return
	var im: Image = _font.render(t.strip_edges(), col)
	var ur := im.get_used_rect()
	if ur.size.x <= 0: return
	var s := Sprite2D.new(); s.centered = false; s.texture = ImageTexture.create_from_image(im.get_region(ur))
	s.position = BOT + Vector2(floorf((256.0 - ur.size.x) * 0.5), y)
	root.add_child(s)

func _process(dt: float) -> void:
	if _done or _font == null: return
	_t += dt * 60.0
	var n := mini(int(_t / CHAR_FRAMES), _desc.length())
	if n != _shown:
		_shown = n
		# wrap on the full text so words do not jump lines as they are typed
		var lines: Array = _font.wrap_lines(_desc, 200)     # DS breaks after "PENGUIN" (173 px; +FORCE would be ~215)
		var left := n; var txt := ""
		for l in lines:
			var take := mini(left, str(l).length())
			txt += str(l).substr(0, take) + "\n"; left -= take + 1
			if left < 0: break
		var im: Image = _font.render(txt.strip_edges(false, true), GREEN, 0, 1)
		_desc_spr.texture = ImageTexture.create_from_image(im)
		_desc_spr.position = BOT + Vector2(floorf((256.0 - im.get_width()) * 0.5), 85.0)     # DS: centred as it grows
	if n >= _desc.length(): _btn.visible = true

func _input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton or e is InputEventMouseMotion or e is InputEventKey): return
	get_viewport().set_input_as_handled()
	if _done or not _btn.visible: return
	if e is InputEventKey:
		if e.pressed and not e.echo and e.keycode in [KEY_ENTER, KEY_SPACE]: _done = true; start_pressed.emit()
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = (e.position - root.position) / root.scale.x - BOT
		if e.pressed: _pressed = BTN.has_point(p)
		elif _pressed and BTN.has_point(p): _done = true; start_pressed.emit()
