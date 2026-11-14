class_name SetupScreen
extends CanvasLayer
## First boot: no game data yet. Asks for the player's own ROM (USA Revision 2 only), checks it, and builds the
## .epf archive (EpfPack) with a progress bar. Emits `done(path)` with the archive's path when it is ready.
## Uses Godot's own font and colours: nothing from the game is available until the archive exists.
signal done(path: String)
const Pack := preload("res://epf/rom/epf_pack.gd")

var _info: Label
var _status: Label
var _bar: ProgressBar
var _pick: Button
var _dlg: FileDialog
var _thread: Thread
var _prog := Vector2i.ZERO
var _result := ""
var _busy := false
var _out := ""

func _ready() -> void:
	layer = 50
	var bg := ColorRect.new(); bg.color = Color8(10, 28, 58); bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	var title := Label.new(); title.text = "Elite Penguin Force - PC Port"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	var sub := Label.new(); sub.text = "First-time setup"; sub.modulate = Color(0.7, 0.82, 1.0)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; sub.add_theme_font_size_override("font_size", 18)
	box.add_child(sub)
	_info = Label.new()
	_info.text = Pack.REQUIREMENT + "\n\nOther regions and Revisions 0 and 1 will not work.\n" + \
		"Select your .nds file and the port will unpack it into a single " + Pack.FILE_NAME + " file.\n" + \
		"After that the ROM is no longer needed. No game data is included with the port."
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.custom_minimum_size = Vector2(760, 0)
	_info.add_theme_font_size_override("font_size", 17)
	box.add_child(_info)
	_pick = Button.new(); _pick.text = "  Select ROM (USA, Revision 2)...  "
	_pick.add_theme_font_size_override("font_size", 20)
	_pick.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pick.pressed.connect(_open_dialog)
	box.add_child(_pick)
	_bar = ProgressBar.new(); _bar.custom_minimum_size = Vector2(520, 22); _bar.visible = false
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_bar)
	_status = Label.new(); _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(760, 0); _status.add_theme_font_size_override("font_size", 17)
	box.add_child(_status)
	box.resized.connect(func() -> void: box.position = (box.get_viewport_rect().size - box.size) * 0.5)
	get_viewport().size_changed.connect(func() -> void: box.position = (box.get_viewport_rect().size - box.size) * 0.5)
	_dlg = FileDialog.new()
	_dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dlg.access = FileDialog.ACCESS_FILESYSTEM
	_dlg.use_native_dialog = true
	_dlg.filters = PackedStringArray(["*.nds ; Nintendo DS ROM"])
	_dlg.title = "Select your Elite Penguin Force ROM (USA, Revision 2)"
	_dlg.file_selected.connect(start)
	add_child(_dlg)
	# testing: EPF_SETUP_ROM=<path> runs the setup without the dialog
	var auto := OS.get_environment("EPF_SETUP_ROM")
	if auto != "": start.call_deferred(auto)

func _open_dialog() -> void:
	if _busy: return
	_dlg.popup_centered_ratio(0.7)

## Check the ROM, then build the archive on a worker thread.
func start(rom_path: String) -> void:
	if _busy: return
	_status.modulate = Color.WHITE; _status.text = "Checking " + rom_path.get_file() + "..."
	await get_tree().process_frame
	var err := Pack.check_rom(rom_path)
	if err != "":
		_status.modulate = Color(1.0, 0.55, 0.5); _status.text = err
		return
	_busy = true; _pick.disabled = true; _bar.visible = true; _bar.value = 0
	_out = Pack.default_path()
	_status.text = "Unpacking game data to " + _out
	_thread = Thread.new()
	_thread.start(func() -> void:
		_result = Pack.build(rom_path, _out, func(d: int, t: int) -> void: _prog = Vector2i(d, t)))

func _process(_dt: float) -> void:
	if not _busy: return
	if _prog.y > 0: _bar.value = 100.0 * _prog.x / _prog.y
	if _thread != null and not _thread.is_alive():
		_thread.wait_to_finish(); _thread = null; _busy = false
		if _result != "":
			_pick.disabled = false; _bar.visible = false
			_status.modulate = Color(1.0, 0.55, 0.5); _status.text = _result
			return
		_status.text = "Done."
		done.emit(_out)
