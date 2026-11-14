extends CanvasLayer
## A chapter's still-picture outro, as the DS plays it after EndMission (measured on M1C1 in DeSmuME):
##  - bottom screen: bg/Cutscenes/<chapter>Outro<n> (256x192), top screen: one GameStrings line per picture
##  - each picture waits for a tap (the DS held picture 1 for over 8 s), then cuts straight to the next
##  - after the last one the game fades to white and free play starts in the chapter's next room
## Single 16:9 screen: the picture at 1:1 in the middle, its line in a strip above it (like the jigsaw).
signal finished

const VIEW := Vector2(384, 216)
const PIC_POS := Vector2(64, 24)
var world: RomWorld
var text: TextTable
var pics: Array = []        # [[bg path, string id], ...]
var i := -1
var root := Node2D.new()
var pic := Sprite2D.new()
var line := Sprite2D.new()
var _font: EpfFont
var _done := false

func setup(w: RomWorld, t: TextTable, list: Array) -> void:
	world = w; text = t; pics = list
	layer = 30
	var back := ColorRect.new(); back.color = Color.BLACK; back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	add_child(root)
	var strip := ColorRect.new(); strip.color = Color8(0, 40, 104); strip.size = Vector2(VIEW.x, PIC_POS.y)
	root.add_child(strip)
	pic.centered = false; pic.position = PIC_POS; root.add_child(pic)
	line.centered = false; root.add_child(line)
	_font = EpfFont.load_font(world.fs, "fonts/faceFront.fnt")
	get_tree().root.size_changed.connect(_layout)
	_layout()
	_next()

func _layout() -> void:
	var win := get_tree().root.get_visible_rect().size
	var u := minf(win.x / VIEW.x, win.y / VIEW.y)
	root.scale = Vector2(u, u)
	root.position = ((win - VIEW * u) * 0.5).floor()

func _next() -> void:
	i += 1
	if i >= pics.size():
		_done = true
		finished.emit()
		return
	var p: Array = pics[i]
	var img := EpfNbfc.load_bg(world, str(p[0]))
	if img: pic.texture = ImageTexture.create_from_image(img)
	line.texture = null
	if _font != null and text != null:
		var s := text.get_text(int(p[1])).replace("%", "").strip_edges()
		# the line uses the full width of the strip; if it still needs two lines it drops to the small UI font
		var im: Image = _font.render(s, Color.WHITE, int(VIEW.x - 8), 1)
		if im != null and im.get_used_rect().size.y > PIC_POS.y - 2:
			var small := EpfFont.load_font(world.fs, "fonts/tinyUI.fnt")
			if small != null: im = small.render(s, Color.WHITE, int(VIEW.x - 8), 1)
		if im != null:
			var ur := im.get_used_rect()
			if ur.size.x > 0:
				line.texture = ImageTexture.create_from_image(im.get_region(ur))
				line.position = Vector2(floorf((VIEW.x - ur.size.x) * 0.5), floorf((PIC_POS.y - ur.size.y) * 0.5))

func _input(e: InputEvent) -> void:
	if _done: return
	var tap: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or \
		(e is InputEventKey and e.pressed and not e.echo and e.keycode in [KEY_ENTER, KEY_SPACE])
	if not tap: return
	get_viewport().set_input_as_handled()
	_next()
