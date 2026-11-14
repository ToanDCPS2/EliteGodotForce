extends Node2D
const Conversation := preload("res://epf/game/conversation.gd")
const ScriptScan := preload("res://epf/game/script_scan.gd")
const Hud := preload("res://epf/ui/hud.gd")
const Iris := preload("res://epf/ui/iris.gd")
const Sfx := preload("res://epf/audio/sfx_player.gd")
var hud
var sfx
var game_text: TextTable      # game strings (objectives, item pop-ups, system lines)
## Playable room viewer: ROM-native room, animated objects, click an object to run its script and read its dialogue.
## Run: godot --path . [-- RoomPrefix]   (game data: game.epf in the game folder, built from your ROM on first boot)
## Single-screen 16:9: 384x216 logical view that scrolls over the room.

const VIEW := Vector2(384, 216)
var world: RomWorld
var chunks: EpfArc
var system_chunk: PackedByteArray
var en: TextTable
var api := GameApi.new()
var room_prefix := "Town0"
var music: MusicPlayer
var flash_rect: ColorRect
var iris                       # room-change wipe (epf/ui/iris.gd)
var _iris_exit: Dictionary = {}
var flash_tw: Tween
var menu_flash := true
var iris_wipe := true          # DS room-change iris (off only for instant headless checks)
var cutscene: CutsceneScreen
var event_filter := 0
var mission := ""                # "" = show every instance; else "chapter.mission" like "1.01"          # dev menu: -1 all, 0 none, 2 summer, 3 halloween, 4 xmas
var room_img: Sprite2D
var objs: Array = []           # {node, dec, frame, t, data, rt}
var cam := Vector2.ZERO
var conv: RefCounted
var pending_npc := -1        # ActivateNpc target, talks as soon as the screen is free
var room_rt: ObjectRuntime
var dbg_events: Array = []
var loop_x := false          # room wraps horizontally (left edge continues from right edge)
var room_clone: Sprite2D
var bg_nodes: Array = []   # {node, par}: parallax background layers that wrap
var _center_cam := false
var _room_focus := -1.0     # SetCursorPos seen while the current room loaded
var _cam_focus := -1.0     # SetCursorPos(x, y): the room opens with the camera centred on x (seen in an emulator)
var _last_win := Vector2.ZERO
var _os_cursor := false
var cursor_mult := 1.0
var title: TitleScreen
var menu: MainMenu
var strict_interest := false   # dev: only fire TOUCHED when the object's interest mask has bit 1 (original ARM rule)
var room_size := Vector2(384, 216)
var dialog: DialogBox
var dev: DevMenu
var cam_target := 0.0
var ui_layer: CanvasLayer
var _ui_built_scale := -1.0
var view_mode := 1            # 0 = fit whole room (letterbox), 1 = fill screen (zoom, scroll)
var rom_cursor := true         # draw the game's own cursor sprites (PC/Spryte/cursor*) instead of the OS cursor
var edge_scroll := true       # scroll when the mouse is near a window edge (fill mode)
var model_scale := 1.1        # 3D model scale (screen px per model unit), tune in dev menu
var model_hires := false     # dev menu: render 3D objects at 4x resolution (off = original DS look)
var model_yoff := 46.0         # 3D model vertical offset (px)

const Pack := preload("res://epf/rom/epf_pack.gd")
const Setup := preload("res://epf/ui/setup_screen.gd")

func _ready() -> void:
	api.exit_default = _exit_default
	var args := OS.get_cmdline_user_args()
	# Game data: only the .epf archive built from the player's own ROM (EpfPack). Without it, the first-boot setup
	# screen asks for the ROM and builds the archive; the game itself never reads a ROM.
	var data_path := ""
	if data_path == "":
		for c in Pack.candidates():
			if not Pack.manifest(c).is_empty(): data_path = c; break
	if data_path == "":
		var su: Node = Setup.new(); add_child(su)
		su.done.connect(func(p: String) -> void: su.queue_free(); _boot(p, args))
		return
	_boot(data_path, args)

func _boot(data_path: String, args: PackedStringArray) -> void:
	for a in args:                            # optional start room: -- <RoomPrefix>
		if not str(a).begins_with("--"): room_prefix = a; break
	world = RomWorld.open(data_path)
	if world == null or world.rooms.is_empty():
		_fatal("Could not read the game data: " + data_path + "\n\n" + Pack.REQUIREMENT)
		return
	chunks = EpfArc.parse(world.rom.file("chunks.arc"))
	system_chunk = chunks.get_chunk("system")
	_load_settings()
	world.set_lang(lang)
	en = TextTable.load_id(world.fs, TextTable.DIALOGUE[lang])
	RenderingServer.set_default_clear_color(Color.BLACK)
	set_filter(bool(settings.get("filter_linear", false)))
	ui_layer = CanvasLayer.new(); ui_layer.layer = 10; add_child(ui_layer)
	var cl := ui_layer
	dialog = DialogBox.new(); cl.add_child(dialog)
	_load_bubble()
	_setup_cursor()
	iris = Iris.new(); add_child(iris)
	iris.closed.connect(_on_iris_closed)
	var fl := CanvasLayer.new(); fl.layer = 30; add_child(fl)
	flash_rect = ColorRect.new(); flash_rect.color = Color(1, 1, 1, 0); flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE; fl.add_child(flash_rect)
	music = MusicPlayer.new(); ui_layer.add_child(music)
	sfx = Sfx.new(); ui_layer.add_child(sfx); dialog.sfx = sfx
	sfx.setup(world.rom.file("sound/sfx.bin"))
	game_text = TextTable.load_id(world.fs, TextTable.GAME_STRINGS[lang])
	hud = Hud.new(); ui_layer.add_child(hud); ui_layer.move_child(hud, 0)
	hud.setup(world, sfx); hud.visible = false; hud.game_text = game_text
	hud.item_dropped.connect(_on_item_dropped)
	hud.items_combined.connect(_on_items_combined)
	hud.item_tapped.connect(func(id: int) -> void: _item_popup(id, false))
	hud.map_pressed.connect(open_map)
	music.setup(world.rom, world.rom.file("sound/music.bin"))
	dev = DevMenu.new(); cl.add_child(dev)
	dev.setup(world.room_prefixes(), self)
	get_viewport().size_changed.connect(_layout)
	# Title screen always comes first; only an explicit --skip-title (headless tests) bypasses it.
	if "--skip-title" in args:
		load_room(room_prefix)
	else:
		_show_title()

## White screen flash used when the menus change (fade from white).
## fade the screen to white over 15 DS frames, then call `then` (the white stays until flash() clears it)
func _fade_white(then: Callable) -> void:
	if flash_rect == null: then.call(); return
	if flash_tw: flash_tw.kill()
	flash_rect.color.a = 0.0
	flash_tw = create_tween(); flash_tw.tween_property(flash_rect, "color:a", 1.0, 0.25)
	flash_tw.tween_interval(0.23)
	flash_tw.tween_callback(then)

func flash(dur := 0.28) -> void:
	if not menu_flash or flash_rect == null: return
	if flash_tw: flash_tw.kill()
	flash_rect.color.a = 1.0
	flash_tw = create_tween(); flash_tw.tween_property(flash_rect, "color:a", 0.0, dur)

func _show_title() -> void:
	if music: music.play_song(0)
	title = TitleScreen.new(); add_child(title); title.setup(world)
	if game_text != null: title.set_label(game_text.get_text(64))   # GameStrings 64: Start / Commencer / Empezar
	title.start_pressed.connect(_on_start)

## ---- minigames ----
## Screen shape per minigame, chosen from what the ROM's graphics can fill:
##  4:3  - Cart Surfer and Snowboarding are chains of 256x192 FLC movies with full-screen overlay canvases (signs,
##         HUD), Dance Challenge and Ice Fishing are fixed single-screen scenes: nothing exists beyond the DS screen,
##         so they run at the original shape, centred with bars
##  16:9 - Jet Pack and Snowcat are levels built from placed sprites (clouds, trees, pads / breakables, pickups) that
##         scroll, so a wider window just shows more of the level
const MINIGAME_ASPECT := {"cartsurfer": "4:3", "snowboarding": "4:3", "dance": "4:3", "icefishing": "4:3",
	"jetpack": "16:9", "snowcat": "16:9"}
var minigame: Node

## EndMission (a chapter's last script line, e.g. Dot at the Lighthouse after 1.01), as the DS does it (DeSmuME):
##  1. the last line closes, a "saving" box shows and the game saves (the save chip changes right here)
##  2. the chapter's still-picture outro plays (bg/Cutscenes/<chapter>OutroN + one line each, tap to go on)
##  3. fade to white, free play at the chapter's next stage in the room the DS puts you in (1.01 -> Beach)
## The free-play object scripts are FP00..FP15; the stage after a mission is its place in the mission order
## (1.01 -> 0.01, whose FP01 Dot in the Dojo starts 1.02). The script repeats EndMission on later touches, so it
## only acts once. The DS box reads "Saving Game Data... Do not turn off the power or remove the DS Card"; the port
## uses the game's own GameStrings 886 "Now Saving ..." since there is no DS Card here.
const MISSION_ORDER := ["1.01", "1.02", "1.03", "2.01", "2.02", "2.03", "3.01", "3.02", "3.03", "3.04", "4.01", "4.02", "4.03", "4.04", "5.01"]
const CHAPTER_END := {
	"1.01": {"pics": [["bg/Cutscenes/M1C1Outro1", 172], ["bg/Cutscenes/M1C1Outro2", 173], ["bg/Cutscenes/M1C1Outro3", 174]],
		"room": "Beach0"},
}
var _ending := false
func end_mission() -> void:
	if _ending or not MISSION_ORDER.has(mission): return
	_ending = true
	if conv != null and conv.active: conv._close()
	api.input_enabled = false
	var done := mission
	var info: Dictionary = CHAPTER_END.get(done, {})
	var next_room := str(info.get("room", room_prefix))
	# 1. saving box, then the save (Continue lands in free play at the next room)
	var box := _saving_box()
	api.vars["%s_complete" % done.replace(".", "_")] = 1
	set_mission("0.%02d" % (MISSION_ORDER.find(done) + 1))
	objective_id = 492                         # free play: GameStrings 492 "Waddle around and have some fun!" (DS)
	room_prefix = next_room
	_write_save()
	await get_tree().create_timer(1.0).timeout
	box.queue_free()
	# 2. outro pictures
	if info.has("pics"):
		var o = preload("res://epf/ui/outro_panels.gd").new()
		add_child(o)
		if hud: hud.visible = false
		o.setup(world, game_text, info["pics"])
		await o.finished
		# 3. white, then free play
		_fade_white(func() -> void:
			o.queue_free()
			if hud: hud.visible = true
			_show_objective_id()
			api.input_enabled = true
			load_room(next_room)
			flash()
			_ending = false)
	else:
		_fade_white(func() -> void:
			api.input_enabled = true
			_show_objective_id()
			load_room(next_room); flash()
			_ending = false)

func _saving_box() -> CanvasLayer:
	var cl := CanvasLayer.new(); cl.layer = 31; add_child(cl)
	var r := ColorRect.new(); r.color = Color8(16, 96, 200); r.size = Vector2(110, 60)
	var win := get_viewport().get_visible_rect().size
	var u := minf(win.x / 384.0, win.y / 216.0)
	r.scale = Vector2(u, u); r.position = (win - r.size * u) * 0.5
	cl.add_child(r)
	var f := EpfFont.load_font(world.fs, "fonts/faceFront.fnt")
	if f != null:
		var im: Image = f.render(game_text.get_text(886).strip_edges(), Color.WHITE, 100, 1)
		if im != null:
			var ur := im.get_used_rect()
			var sp := Sprite2D.new(); sp.centered = false; sp.texture = ImageTexture.create_from_image(im.get_region(ur))
			sp.position = (r.size - Vector2(ur.size)) * 0.5
			r.add_child(sp)
	return cl

## Mission microgames started by scripts (StartMiniGame(type, variant)). The scripts poll GetGameState: it reads
## _const.MISSION (7) in the world, the game's own id while it runs (JIGSAW 8...), then MISSION again, and they read
## the result with GetMinigameOutput1 (1 = solved).
const GS_MISSION := 7
func start_script_minigame(kind: int, v: int) -> void:
	if minigame != null: return
	match kind:
		8:   # JIGSAW
			api.game_state = kind
			var j = preload("res://epf/minigames/jigsaw.gd").new()
			minigame = j; add_child(j)
			j.setup(world, v, game_text, sfx)
			if hud: hud.visible = false
			j.finished.connect(func(ok: bool) -> void:
				api.minigame_output1 = 1 if ok else 0
				j.queue_free(); minigame = null
				if hud: hud.visible = true
				api.game_state = GS_MISSION
				flash())
		_:
			push_warning("StartMiniGame %d not implemented" % kind)
## The island map (MAP button). The room each place leads to, and which places exist, come from the current story
## stage's room list in overlay 0 (stage 11/12/13 = mission 1 chapters 1-3 by their contents; 0 = the full list,
## used for free play; the other story chapters still use the full list until their stage numbers are checked).
const MapScreen := preload("res://epf/ui/map_screen.gd")
const STAGE_LIST := {"1.01": 11, "1.02": 12, "1.03": 13}
var map_data: Dictionary = {}
var map_level := ""                 # the place on the map the player was last in
var _prefix_by_upper: Dictionary = {}
func _stage_rooms() -> Dictionary:
	if map_data.is_empty():
		map_data = OverlayMeta.scan_map(world.rom)
		for p in world.room_prefixes(): _prefix_by_upper[str(p).to_upper()] = p
	var lists: Array = map_data.get("lists", [])
	if lists.is_empty(): return {}
	var idx: int = STAGE_LIST.get(mission, 0)
	var out := {}
	for r in lists[mini(idx, lists.size() - 1)]:
		if r["level"] != "" and not out.has(r["level"]) and _prefix_by_upper.has(r["room"]):
			out[r["level"]] = _prefix_by_upper[r["room"]]
	return out

func _note_map_level() -> void:
	var sr := _stage_rooms()
	for lv in sr:
		if sr[lv] == room_prefix: map_level = lv

func open_map() -> void:
	if minigame != null or _ending or (conv != null and conv.active) or dialog.visible: return
	var sr := _stage_rooms()
	if sr.is_empty(): return
	var consts = room_rt.vm.G.get_v("_const") if room_rt != null else null
	var al: Array = []
	for id in api.map_alerts:
		var a: Array = api.map_alerts[id]
		var tn := "STORY_MISSION"
		if consts != null:
			for k in MapScreen.ALERT_ICON:
				var v = consts.get_v(k)
				if v != null and int(v) == int(a[0]): tn = k
		al.append({"type": tn, "pos": Vector2(a[1], a[2]), "top": Vector2(a[3], a[4]) if a.size() > 4 else Vector2(-1, -1)})
	var here := map_level if sr.has(map_level) else str(sr.keys()[0])
	var m = MapScreen.new()
	minigame = m; add_child(m)
	if hud: hud.visible = false
	m.setup(world, sfx, map_data, sr, here, al, player_color)
	flash()
	var done := func() -> void:
		m.queue_free(); minigame = null
		if hud: hud.visible = true
	m.closed.connect(func() -> void: done.call(); flash())
	m.entered.connect(func(room: String) -> void:
		_fade_white(func() -> void:
			done.call()
			load_room(room); flash()))

## Started from the Mini Games menu (or the dev menu); the menu waits underneath and comes back on the Cart Surfer
## screen with the high score updated.
func start_cart_surfer(opts: Dictionary = {}) -> void:
	if minigame != null: return
	if dev: dev.visible = false
	var col := player_color
	if menu != null:
		var sv: Dictionary = menu.read_save()
		col = str(sv.get("color", menu.player_color if menu.player_color != "" else col))
	minigame = preload("res://epf/minigames/cart_surfer.gd").new(); add_child(minigame)
	minigame.music = music
	minigame.text = game_text
	minigame.setup(world, sfx, col)
	minigame.covered.connect(func() -> void:          # DS: the menu fades to white, then the game takes over
		if menu != null: menu.visible = false)
	minigame.finished.connect(func(sc: int, ok: bool) -> void:
		print("CARTSURFER ", sc, " ", ok)
		minigame.queue_free(); minigame = null
		if menu != null: music.play_song(18)          # back to the menu song
		elif room_prefix != "": music.play_room(room_prefix)
		flash()
		var earned := sc / 10                              # DeSmuME: 80 points -> 8 coins
		if menu != null:
			var prev := int(menu.mini_scores().get("cartsurfer", 0))
			menu.set_mini_score("cartsurfer", sc)
			var total: int = menu.add_coins(earned)
			menu.visible = true; menu.show_cs_results(sc, earned, total, sc > prev, ok)
		elif api != null:
			api.coins += earned
			_write_save())                                   # DS: a finished minigame saves (coins, score)

## Plays a ROM FLC movie as a mission-intro overlay does (see CutsceneScreen), then calls `done`.
## `sched` / `loop_at`: the overlay's per-frame holds and tail loop. Falls back to `done` if the movie is missing.
func play_movie(path: String, done: Callable, caption := "", sched: Dictionary = {}, loop_at := -1) -> void:
	var bytes := world.loc_bytes(path)
	cutscene = CutsceneScreen.new(); add_child(cutscene)
	if bytes.size() > 0 and cutscene.setup(bytes, sched, loop_at):
		if flash_tw: flash_tw.kill()
		if flash_rect: flash_rect.color.a = 0.0      # the white gives way to the movie's fade-in from black
		if caption != "":
			var f := EpfFont.load_font(world.fs, "fonts/faceFront.fnt")
			var img: Image = f.render(caption, Color.WHITE, 206, 1) if f != null else null
			cutscene.set_caption(EpfNbfc.load_bg(world, "bg/Menus/Menus_bottom"), img)
		cutscene.finished.connect(func() -> void:
			cutscene.queue_free(); cutscene = null
			flash(0.25); done.call())
		return
	cutscene.queue_free(); cutscene = null
	done.call()

## Title "Start": the ROM's Intro movie plays first (letterboxed), then the main menu.
## ---- settings (Options): language + the DS Microphone screen's Volume (0-3) and Sensitivity (0-8) ----
var SETTINGS_PATH: String = Pack.save_path("settings.json")   # <game folder>/saves/
var settings := {"lang": "en", "mic_volume": 1, "mic_sensitivity": 5, "save_every_change": false}
## Saving like the DS (measured on its save chip in DeSmuME): finishing a minigame saves (coins, high score); talking,
## items, room changes, accepting a mission and pause -> Quit do not. Finishing a chapter (EndMission) is the likely
## other save point (not yet confirmed). "Save after every change" in the F1 menu is the non-original alternative.
var save_every_change := false
var lang := "en"
func _load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var j = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if j is Dictionary: settings.merge(j, true)
	lang = str(settings.get("lang", "en"))
	save_every_change = bool(settings.get("save_every_change", false))

## The F1 menu's sharp/smooth choice, for everything drawn in 2D: the room (this node's own filter) and every
## screen on its own CanvasLayer (HUD, menus, map, minigames), which take the viewport's default.
func set_filter(linear: bool) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if linear else CanvasItem.TEXTURE_FILTER_NEAREST
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR if linear \
		else Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if bool(settings.get("filter_linear", false)) != linear:
		settings["filter_linear"] = linear; _save_settings()

func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(settings))

func _set_lang(l: String) -> void:
	lang = l; settings["lang"] = l; _save_settings()
	world.set_lang(l)
	en = TextTable.load_id(world.fs, TextTable.DIALOGUE[l])
	game_text = TextTable.load_id(world.fs, TextTable.GAME_STRINGS[l])
	hud.game_text = game_text; hud._tex.clear()
	_load_bubble()
	if menu != null: menu.set_text(game_text)

func _on_start() -> void:
	if sfx: sfx.play(Sfx.UI_BUTTON)
	if title != null: title.queue_free(); title = null
	play_movie("flc/Intro.flc", _show_menu)

func _show_menu() -> void:
	if music: music.play_song(18)
	menu = MainMenu.new(); add_child(menu); menu.setup(world, game_text)
	menu.settings = settings
	menu.lang_changed.connect(_set_lang)
	menu.settings_changed.connect(_save_settings)
	menu.on_screen = flash
	menu.on_click = func() -> void: sfx.play(Sfx.UI_BUTTON)
	menu.start_game.connect(_on_start_game)
	menu.start_minigame.connect(func(game: String, opts: Dictionary) -> void:
		if game == "cartsurfer": start_cart_surfer(opts))
	menu.back_to_title.connect(func() -> void:
		if menu != null: menu.queue_free(); menu = null
		_show_title())

## Campaign: a new game plays the mission-1 newspaper intro, then the story starts at mission 1.01 in Town.
var player_name := ""
var player_color := "blue"
## \x0b in GameStrings / dialogue is the player's name ("Congratulations Agent \x0b!").
func fmt(t: String) -> String:
	return t.replace(char(11), player_name).replace("%", "").strip_edges()

func _on_start_game(new_game: bool) -> void:
	if menu != null:
		player_name = menu.player_name; player_color = menu.player_color
		hud.player_doll = menu.doll_image()
		if new_game:
			# Missions on a fresh profile: the stylus help screen first, then free play 0.00 in Town
			menu.show_tutorial(func() -> void:
				if menu != null: menu.queue_free(); menu = null
				_new_story())
			return
		menu.queue_free(); menu = null
	if new_game:
		_new_story()
	else:
		var sv := _read_save()
		if sv.has("vars"): api.vars = sv["vars"]
		api.exits_locked.clear()
		for k in sv.get("exits", {}): api.exits_locked[int(k)] = bool(sv["exits"][k])
		world_shown.clear()
		for k in sv.get("shown", {}):
			world_shown[int(k)] = bool(sv["shown"][k])
		api.states.clear()
		for k in sv.get("states", {}):
			api.states[int(k)] = str(sv["states"][k])
		api.conv_counts.clear()
		for k in sv.get("convs", {}):
			api.conv_counts[int(k)] = int(sv["convs"][k])
		api.suitcase_enabled.clear()
		for k in sv.get("suitcase", {}):
			api.suitcase_enabled[int(k)] = bool(sv["suitcase"][k])
		api.suitcase_equipped.clear()
		for k in sv.get("worn", {}):
			api.suitcase_equipped[int(k)] = bool(sv["worn"][k])
		api.puffles_enabled.clear()
		for k in sv.get("puffles", {}):
			api.puffles_enabled[int(k)] = bool(sv["puffles"][k])
		if sv.has("inventory"):
			api.inventory.clear()
			for k in sv["inventory"]: api.inventory[int(k)] = 1
			hud.set_items(api.inventory)
		player_name = str(sv.get("name", player_name)); player_color = str(sv.get("color", player_color))
		api.coins = int(sv.get("coins", 100))
		# saves from before the map screen existed stored "map": false everywhere
		api.map_shown = bool(sv.get("map", true)) if sv.has("map_level") else str(sv.get("mission", "")) != "1.01"
		hud.map_enabled = api.map_shown
		api.map_alerts = {}
		var sal = sv.get("alerts", {})
		if sal is Dictionary:
			for k in sal: api.map_alerts[int(k)] = sal[k]
		map_level = str(sv.get("map_level", ""))
		api.puffle = int(sv.get("puffle", -1)); hud.puffle_item = api.puffle
		flash()
		room_prefix = str(sv.get("room", STORY_START_ROOM))
		set_mission(str(sv.get("mission", "0.00")))
		objective_id = int(sv.get("objective", -1)); _show_objective_id()

## The game's real order (scripts + ARM): a new game is free-play mission 0.00 ("FP00") in Town: town0.luc sets
## FP00_intro, objective GameStrings 492 "Waddle around and have some fun!" and points at Aunt Arctic
## (FP00_Town0_NPC_AuntArctic: "...there is a copy of this week's paper inside the Coffee Shop."). The Coffee Shop
## newspaper (FP00_CoffeeShop0_ItemsFP00_Newspaper) calls StartMission(11) = chapter 1 mission 1, which plays
## M1C1INTRO (the newspaper movie + GameStrings 159) and starts mission 1.01 where the player stands (Coffee Shop):
## coffeeshop0.luc then sets objective 175 and wakes the blue puffle. Missions alternate with free-play: FP01 ends in
## StartMission(12), FP02 in 13, ... (StartMission(n) = chapter n/10, mission n%10).
const STORY_START_ROOM := "Town0"
func _new_story() -> void:
	api.vars.clear(); api.inventory.clear(); api.exits_locked.clear(); api.coins = 100; api.conv_counts.clear()   # profiles start with 100 coins
	world_shown.clear(); api.states.clear(); api.suitcase_enabled.clear(); api.suitcase_equipped.clear(); api.puffles_enabled.clear()
	hud.set_items(api.inventory); hud.puffle_item = -1; hud.map_enabled = false; api.map_shown = false; api.puffle = -1
	_begin_story()

func _begin_story() -> void:
	flash()
	if dev != null: dev.sel_mission = MISSION_LIST_INDEX.get("0.00", 0)
	room_prefix = STORY_START_ROOM
	set_mission("0.00")
	_write_save()

const MISSION_LIST_INDEX := {"0.00": 16, "1.01": 1}
## Cutscene played by StartMission before a mission begins: [movie, caption GameStrings id, holds, loop-from].
## M1C1INTRO (ov37), DeSmuME: frame 0 held 140 DS frames, 1 held 61, 5 held 108, 16 held 228, the rest ~5;
## after frame 16 it goes back to 6 and repeats until a tap.
const MISSION_INTRO := {"1.01": ["flc/M1C1Intro03NewsPaperFull.flc", 159, {0: 140, 1: 61, 4: 4, 5: 108, 16: 228}, 6]}
func start_mission(code: int) -> void:
	var m := "%d.%02d" % [code / 10, code % 10]
	if conv != null and conv.active: conv._close()
	var go := func() -> void:
		set_mission(m)
		if dev != null and MISSION_LIST_INDEX.has(m): dev.sel_mission = MISSION_LIST_INDEX[m]
		if save_every_change: _write_save()          # the DS does not save when a mission is accepted
	if MISSION_INTRO.has(m):
		var mi: Array = MISSION_INTRO[m]
		# DS: the room fades to white over 15 frames, holds, then the movie fades in from black
		_fade_white(func() -> void: play_movie(mi[0], go, fmt(game_text.get_text(mi[1])), mi[2], mi[3]))
	else:
		# the briefing: "MISSION n:", the mission's name, its description, START MISSION
		var n := STORY_ORDER.find(m) + 1
		if n <= 0 or minigame != null:
			flash(); go.call(); return
		_fade_white(func() -> void:
			var mi2 = preload("res://epf/ui/mission_intro.gd").new()
			minigame = mi2; add_child(mi2)
			if hud: hud.visible = false
			var head := game_text.get_text(48 + n) if n >= 2 else game_text.get_text(74).strip_edges() + " 1:"
			mi2.setup(world, head, game_text.get_text(190 + n), game_text.get_text(158 + n), game_text.get_text(255))
			flash()
			mi2.start_pressed.connect(func() -> void:
				_fade_white(func() -> void:
					mi2.queue_free(); minigame = null
					if hud: hud.visible = true
					go.call(); flash())))

var SAVE_PATH: String = Pack.save_path("save.json")
func _save_text() -> String:
	return JSON.stringify({"started": true, "room": room_prefix, "mission": mission, "vars": api.vars,
		"inventory": api.inventory.keys(), "name": player_name, "color": player_color, "coins": api.coins,
		"map": api.map_shown, "puffle": api.puffle, "exits": api.exits_locked,
		"shown": world_shown, "states": api.states, "convs": api.conv_counts,
		"suitcase": api.suitcase_enabled, "worn": api.suitcase_equipped, "puffles": api.puffles_enabled,
		"objective": objective_id, "alerts": api.map_alerts, "map_level": map_level})

var _saved_text := ""
var objective_id := -1      # GameStrings id of the current objective (saved as the id so it follows the language)
func _show_objective_id() -> void:
	if objective_id >= 0 and game_text != null:
		hud.show_objective(game_text.get_text(objective_id).replace("%", "").strip_edges())
func _write_save() -> void:
	var t := _save_text()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null: return
	f.store_string(t); _saved_text = t

## Autosave: everything the scripts change that the save holds (vars, items, coins, object states, conversation
## counts, suitcase, puffles, exits, room) is written as soon as it changes and no conversation or cutscene is
## mid-way, so nothing done in the world is lost on quitting. Checked twice a second; only writes on a change.
var _autosave_t := 0.0
func _autosave(dt: float) -> void:
	_autosave_t += dt
	if _autosave_t < 0.5: return
	_autosave_t = 0.0
	if not save_every_change or not _story_active(): return
	if (conv != null and conv.active) or cutscene != null or minigame != null: return
	var t := _save_text()
	if t != _saved_text: _write_save()

func _story_active() -> bool:
	return menu == null and title == null and FileAccess.file_exists(SAVE_PATH)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and save_every_change and world != null and menu == null and title == null and minigame == null and FileAccess.file_exists(SAVE_PATH):
		_write_save()

func _read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH): return {}
	var j = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return j if j is Dictionary else {}

func _fatal(msg: String) -> void:
	push_error(msg)
	var cl := CanvasLayer.new(); add_child(cl)
	var l := Label.new(); l.text = msg; l.position = Vector2(8, 8); l.size = Vector2(368, 200)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.add_theme_font_size_override("font_size", 8)
	cl.add_child(l)
	get_window().content_scale_size = Vector2i(VIEW)

func set_mission(m: String) -> void:
	mission = m
	if m == "": api.active_chapter = 0; api.active_mission = 0
	else:
		# "1.02" is mission 1, chapter 2 to the scripts (Dojo0: GetActiveMission() == 1 and GetActiveChapter() == 2;
		# free play stage 4 is mission 0, chapter 4)
		var p := m.split("."); api.active_mission = int(p[0]); api.active_chapter = int(p[1])
	# DS: a new stage starts with the MAP button there (after chapter 1.01's ending it is on the Beach HUD though no
	# script calls ShowMap); a stage that should not have it hides it itself (Coffee Shop, 1.01: HideMap)
	api.map_shown = true
	if hud: hud.map_enabled = true
	load_room(room_prefix)

func load_room(prefix: String) -> void:
	room_prefix = prefix
	if music:
		var ch := api.active_mission; var sb := api.active_chapter
		music.play_room(prefix, ch - 1 if ch > 0 else -1, sb)
	for c in get_children():
		if c is CanvasLayer: continue
		c.queue_free()
	objs.clear(); models3d.clear(); model_touch.clear(); api.events.clear(); bg_nodes.clear(); pending_npc = -1; pending_exit = {}
	var ev := event_filter
	var r := world.compose_layers(prefix)
	if r.is_empty(): return
	room_img = Sprite2D.new(); room_img.centered = false
	room_img.texture = ImageTexture.create_from_image(r["image"])
	for bg in r.get("bgs", []):
		var bs := Sprite2D.new(); bs.centered = false
		bs.texture = ImageTexture.create_from_image(bg["image"])
		bs.region_enabled = true; bs.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		add_child(bs)
		bg_nodes.append({"node": bs, "par": bg["par"]})
	add_child(room_img)
	room_size = Vector2(r["image"].get_size())
	var met := _room_metrics(r["image"])
	room_size.y = float(met["h"]); loop_x = world.room_wraps(prefix)   # ROM flag (map record +0x23), not a guess from the picture; room_clone = null
	if loop_x:
		room_clone = Sprite2D.new(); room_clone.centered = false; room_clone.texture = room_img.texture
		room_clone.position = Vector2(room_size.x, 0); add_child(room_clone)
	var ov: int = r["overlay"]
	var cand: Array = []
	for o in world.objects.get(ov, world.objects.get(str(ov), [])):
		if not RomWorld.visible(o, ev): continue
		if not RomWorld.is_door(o) and not RomWorld.mission_ok(o, mission): continue
		cand.append(o)
	for o in RomWorld.pick_doors(cand, mission):
		if RomWorld.is_inventory_def(o): continue
		if world.is_model_object(o):
			_add_model_object(o)
			continue
		var k := world._key_for(o)
		if k == "": continue
		var dec := world.sprite(k)
		if dec.is_empty() or dec["frames"].is_empty(): continue
		var spr := Sprite2D.new(); spr.centered = false
		var cen = dec.get("center"); if cen == null: cen = [0, 0]
		spr.position = Vector2(int(o["x"]) - int(cen[0]), int(o["y"]) - int(cen[1]))
		var tex: Array = []
		for f in dec["frames"]: tex.append(ImageTexture.create_from_image(f["image"]))
		spr.texture = tex[0]
		add_child(spr)
		var rt: ObjectRuntime = null
		if o["script"] != null:
			var cb := chunks.get_chunk(str(o["script"]).get_file().get_basename())
			if not cb.is_empty():
				rt = ObjectRuntime.create({}, system_chunk, cb, api, int(o["id"]), str(o["name"]))
				rt.fire(api, "CREATED")
		if int(o["event"]) == RomWorld.HIDDEN_UNTIL_ACTIVATED: spr.visible = false
		api.positions[int(o["id"])] = Vector2(float(o.get("x", 0)), float(o.get("y", 0)))   # GetX/GetY: the object's room position
		var ent := {"bx": spr.position.x, "node": spr, "tex": tex, "dec": dec, "frame": 0, "t": 0.0, "data": o, "rt": rt}
		if RomWorld.is_door(o):
			# state art is <Door>_closed/_opening/_open/_closing next to the plain <Door> sprite
			var base := k.trim_suffix("_closed")
			if rdt_has(base + "_closed"): _setup_door(ent, base)
		objs.append(ent)
	_loading_room = true
	_hide_unadded()
	_show_room_puffle()
	# room script: runs setupItems(mission, chapter) etc. => initial spawn/visibility of mission-variant objects
	var rcb := chunks.get_chunk(prefix.to_lower())
	if not rcb.is_empty():
		var rrt := ObjectRuntime.create({}, system_chunk, rcb, api, 0, prefix)
		rrt.fire(api, "CREATED")
		room_rt = rrt
	_note_map_level()
	if hud: hud.set_room(prefix, _mission_line(), api.coins)
	dbg_events = api.events.duplicate()
	_cam_focus = -1.0
	_apply_events(0)
	_restore_world_state()
	_loading_room = false
	api.events.clear()
	_co_rts.clear(); _cam_stack.clear()
	cam = Vector2.ZERO
	_center_cam = true
	_apply_cam()

func _process(dt: float) -> void:
	if world == null: return                  # first-boot setup still running
	_autosave(dt)
	var cw := get_viewport().get_visible_rect().size
	if cw != _last_win:
		_last_win = cw; _layout()
	_process_models(dt)
	_process_puffle(dt)
	if hud: hud.visible = title == null and menu == null and cutscene == null and room_img != null
	if pending_npc >= 0 and not dialog.visible and cutscene == null and menu == null and title == null:
		var pid := pending_npc; pending_npc = -1
		for o in objs:
			if int(o["data"].get("id", -1)) == pid and o["rt"] != null:
				var szi: Vector2 = o["dec"]["frames"][o["frame"]]["image"].get_size()
				_run_touch(str(o["data"]["name"]), o["rt"], (o["node"].position + Vector2(szi.x * 0.5, 0.0)) * scale + position, o["data"])
				break
	_update_cursor()
	_update_doors(dt)
	for o in objs:
		if o.has("door"): continue
		var fr: Array = o["dec"]["frames"]
		var oid := int(o["data"].get("id", -1))
		if fr.size() < 2:
			if o.get("state_once", false): api.anim_playing[oid] = false
			continue
		o["t"] += dt * 1000.0
		var d: float = maxf(float(fr[o["frame"]]["dur_ms"]), 16.0)
		if o["t"] >= d:
			o["t"] -= d
			if o.get("state_once", false) and o["frame"] + 1 >= fr.size():
				o["t"] = 0.0; api.anim_playing[oid] = false     # a non-looping state anim holds its last frame
			elif o.get("state_revert", false) and o["frame"] + 1 >= fr.size() and not o.has("pre_talk"):
				_switch_state(oid, "")                          # a play-once state anim: back to the idle one
			else:
				o["frame"] = (o["frame"] + 1) % fr.size()
				o["node"].texture = o["tex"][o["frame"]]
	if _popup_open and not dialog.visible:
		_popup_open = false; api.popup_visible = false
	_pump_coroutines()
	if _talk_id >= 0 and api.positions.has(_talk_id):
		var fp: Vector2 = api.positions[_talk_id]
		var wx := fp.x * scale.x + position.x
		if loop_x and wx < 0.0: wx += room_size.x * scale.x
		var nf := Vector2(wx, fp.y * scale.y + position.y)
		if dialog.speaker_feet.distance_to(nf) > 0.5:
			dialog.speaker_feet = nf
			if dialog.visible and dialog.opt_nodes.is_empty(): dialog._refresh()
	var dir := Input.get_axis("ui_left", "ui_right")
	var dirv := Input.get_axis("ui_up", "ui_down")
	if edge_scroll and view_mode == 1 and get_window().has_focus():
		var vp := get_viewport(); var win := vp.get_visible_rect().size; var mp := vp.get_mouse_position()
		# Fullscreen: the mouse is always over the game, but Godot's Windows fullscreen window is a pixel larger than
		# the screen, so at the very edge the cursor can read as just outside the view - clamp it in instead of
		# ignoring it. Windowed: a few pixels of slack so the outermost pixel still scrolls.
		var fs := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		var inside := fs or Rect2(Vector2.ZERO, win).grow(4.0).has_point(mp)
		mp = mp.clamp(Vector2.ZERO, win)
		if inside:
			var zone := minf(win.x, win.y) * 0.08
			if mp.x < zone: dir -= 1.0 - mp.x / zone
			elif mp.x > win.x - zone: dir += 1.0 - (win.x - mp.x) / zone
			if mp.y < zone: dirv -= 1.0 - mp.y / zone
			elif mp.y > win.y - zone: dirv += 1.0 - (win.y - mp.y) / zone
	if (dir != 0.0 or dirv != 0.0) and not dialog.visible:
		cam.x += dir * 240.0 * dt; cam.y += dirv * 240.0 * dt; _layout()

## Fill-mode metrics: usable height (256-px rooms have a flat unused strip at the bottom) and whether the room wraps horizontally.
## Looping rooms: the copy of something at room x (left edge, width w) to draw so it shows wherever any part of it
## overlaps the view - its right edge is kept in [cam.x, cam.x + room width). A fixed margin made wide objects (and
## anything left of the camera) jump to the far side and vanish while still partly on screen.
func _wrap_x(x: float, w: float) -> float:
	return fposmod(x + w - cam.x, room_size.x) + cam.x - w

func _obj_w(n: Sprite2D) -> float:
	return float(n.texture.get_width()) if n.texture != null else 64.0

func _room_metrics(im: Image) -> Dictionary:
	var W := im.get_width(); var H := im.get_height()
	var blank := 0
	while blank < H - 1:
		var y := H - 1 - blank
		var base := im.get_pixel(0, y); var same := true
		for x in range(0, W, 3):
			var c := im.get_pixel(x, y)
			if absf(c.r - base.r) + absf(c.g - base.g) + absf(c.b - base.b) + absf(c.a - base.a) > 0.04: same = false; break
		if not same: break
		blank += 1
	var h := clampi(H - blank, mini(192, H), H)
	var seam := 0.0; var n := 0
	for y in range(0, H, 2):
		var a := im.get_pixel(0, y); var b := im.get_pixel(W - 1, y)
		if a.a < 0.5 or b.a < 0.5: continue
		seam += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b); n += 1
	var lp := W >= 500 and n > 0 and seam / float(n) < 0.065
	return {"h": h, "loop": lp}

## Stacked mission variants (e.g. DotMailbox / DotMailbox2): the game spawns only one and swaps them via AddItem/DelItem.
## Objects that scripts of this room only ever AddItem start absent.
## The player's puffle (after SetPuffle). Every room has a hidden, script-less "BluePuffle" spot that sets the puffle's ground
## line; on the DS the puffle stands at the bottom-middle of the view and hops after the camera when it scrolls
## (NPC/Puffles/Blue/BluePuffle_walkLeft / _walkRight, idle BluePuffle). Seen in DeSmuME (M1C1 Coffee Shop -> Town).
## DS puffle state machine (ARM 0x21213bc table: INTRO IDLE IDLE_TO WALKING WALKING_TO TURN IDLE2READY READY FAIL
## READY_TO STANDBY SHOOT READY2IDLE JUMP), measured in DeSmuME (M1C1 Snow Forts):
##  - follows the camera target (ARM 0x2121efc): walks once it is >= 110 px away, ~3.8 px per frame, until it gets there
##  - idle: plays _TO every 600-900 frames (random); ready: _readyTO after 623 frames, then every 180-230
##  - ready + tap the ground: _shoot, a snowball flies to the spot (sound 156 at launch, 24 frames), splats (sound 57),
##    and the puffle stays ready; tap an object that accepts it: same, and the object gets COLLIDED as it lands
const PUFFLE_SPEED := 228.0       # room px per second while walking (DS: ~3.8 px per frame)
const PUFFLE_FOLLOW := 110.0      # starts walking when the camera target is this far away
var _puf_idle_t := 0.0            # seconds until the next idle / ready fidget
var _puf_ready_first := true
var _puf_ammo := 0                # DS: 3 snowballs per ready; the 3rd throw stands the puffle down (ARM 0x2121cf7)
var _puf: Sprite2D
var _puf_anims := {}
var _puf_state := ""
var _puf_after := ""              # one-shot puffle animation playing: what follows it
var _puf_t := 0.0
var _puf_i := 0
var _puf_x := 0.0
var _puf_y := 0.0

func _puf_anim(k: String) -> Dictionary:
	if not _puf_anims.has(k):
		var d: Dictionary = world.sprite("NPC/Puffles/Blue/" + k)
		var a := {}
		if not d.is_empty() and d.has("frames") and d["frames"].size() > 0:
			a = {"tex": [], "dur": [], "center": Vector2(d.get("center", [0, 0])[0], d.get("center", [0, 0])[1])}
			for f in d["frames"]:
				a["tex"].append(ImageTexture.create_from_image(f["image"])); a["dur"].append(maxf(float(f.get("dur_ms", 100)), 16.0) / 1000.0)
		_puf_anims[k] = a
	return _puf_anims[k]

var _puf_trace := OS.get_environment("PUFTRACE") != ""
func _puf_set(k: String) -> void:
	if _puf_state == k: return
	if _puf_trace: print("PUF ", Time.get_ticks_msec(), " ", k, " x ", int(_puf_x))
	_puf_state = k; _puf_i = 0; _puf_t = 0.0

func _show_room_puffle() -> void:
	var spot = null
	for o in objs:
		if str(o["data"]["name"]) == "BluePuffle" and o["data"].get("script") == null and int(o["data"].get("event", 0)) == RomWorld.HIDDEN_UNTIL_ACTIVATED:
			o["node"].visible = false; spot = o
	if _puf != null and is_instance_valid(_puf): _puf.queue_free()
	_puf = null
	if api.puffle < 0 or spot == null: return
	_puf = Sprite2D.new(); _puf.centered = false; _puf.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	_puf.z_index = int(spot["node"].z_index)
	spot["node"].get_parent().add_child(_puf)
	_puf_y = float(spot["data"]["y"])
	var vis := get_viewport().get_visible_rect().size / maxf(scale.x, 0.01)
	_puf_x = cam.x + vis.x * 0.5 if not _center_cam else float(spot["data"]["x"])
	_puf_state = ""; _puf_set("BluePuffle"); _puf_mode = ""; _puf_after = ""
	_puf_idle_t = randf_range(10.0, 15.0)

## arriving in a room: the puffle is already in the middle of the view
func _puf_snap() -> void:
	if _puf == null or not is_instance_valid(_puf): return
	var vis := get_viewport().get_visible_rect().size / maxf(scale.x, 0.01)
	_puf_x = cam.x + vis.x * 0.5

func _process_puffle(dt: float) -> void:
	if _puf == null or not is_instance_valid(_puf): return
	var vis := get_viewport().get_visible_rect().size / maxf(scale.x, 0.01)
	var target := cam.x + vis.x * 0.5
	var dx := target - _puf_x
	if loop_x: dx = fposmod(dx + room_size.x * 0.5, room_size.x) - room_size.x * 0.5
	var walking := _puf_state.begins_with("BluePuffle_walk")
	if _puf_mode == "" and (_puf_after == "" or _puf_state == "BluePuffle_TO"):
		if absf(dx) >= PUFFLE_FOLLOW or (walking and absf(dx) > 4.0):
			if _puf_after != "": _puf_after = ""          # a fidget is cut short by walking off
			_puf_set("BluePuffle_walkRight" if dx > 0 else "BluePuffle_walkLeft")
			_puf_x += signf(dx) * minf(absf(dx), PUFFLE_SPEED * dt)
			_puf_idle_t = randf_range(10.0, 15.0)
		elif _puf_after == "":
			_puf_set("BluePuffle")
			_puf_idle_t -= dt
			if _puf_idle_t <= 0.0:
				_puf_idle_t = randf_range(10.0, 15.0)
				_puf_play_once("BluePuffle_TO", "BluePuffle")
	elif _puf_mode == "ready" and _puf_after == "" and _puf_state == "BluePuffle_ready":
		_puf_idle_t -= dt
		if _puf_idle_t <= 0.0:
			_puf_idle_t = randf_range(3.0, 3.8)
			_puf_play_once("BluePuffle_readyTO", "BluePuffle_ready")
	var a := _puf_anim(_puf_state)
	if a.is_empty(): a = _puf_anim("BluePuffle")
	if a.is_empty(): return
	_puf_t += dt
	while _puf_t >= a["dur"][_puf_i % a["tex"].size()]:
		_puf_t -= a["dur"][_puf_i % a["tex"].size()]
		if _puf_after != "" and _puf_i + 1 >= a["tex"].size():
			# one-shot animation finished: chain to the next one
			var nx := _puf_after; _puf_after = ""
			if nx == "BluePuffle_ready2idle": _puf_after = "BluePuffle"
			if nx == "BluePuffle":
				if _puf_mode != "": _puf_idle_t = randf_range(10.0, 15.0)
				_puf_mode = ""
			elif nx == "BluePuffle_ready":
				if _puf_mode != "ready":
					_puf_idle_t = 623.0 / 60.0 if _puf_ready_first else randf_range(3.0, 3.8)
					_puf_ready_first = false
				_puf_mode = "ready"
			_puf_set(nx); a = _puf_anim(nx)
			if a.is_empty(): return
			continue
		_puf_i = (_puf_i + 1) % a["tex"].size()
	_puf.texture = a["tex"][_puf_i % a["tex"].size()]
	_puf.position = Vector2(_puf_x, _puf_y) - a["center"]
	if loop_x: _puf.position.x = _wrap_x(_puf.position.x, float(a["tex"][0].get_width()))

func _hide_unadded() -> void:
	var idt = null
	var added := {}; var deled := {}
	var seen := {}
	for o in objs:
		var sp = o["data"].get("script")
		if sp == null or seen.has(sp): continue
		seen[sp] = true
		var cb := chunks.get_chunk(str(sp).get_file().get_basename())
		var r := ScriptScan.scan(cb)
		for n in r["add"]: added[n] = true
		for n in r["del"]: deled[n] = true
		if idt == null and o["rt"] != null: idt = o["rt"].vm.G.get_v("_id")
	if idt == null: return
	for n in added:
		if deled.has(n): continue
		var id = idt.get_v(n)
		if id != null: _set_obj_shown(int(id), false)
	# ROM start flag: a scripted object is in the room from the start only when bit 0x100 is set in its def
	# (word 8, or the high half of word 7 in the short record that has no word 8). Checked in DeSmuME on M1C1
	# Snow Forts: the snowman (0x100) is there, the hat penguin and the hat on the clock (0) only appear after
	# the snowman's AddItem. Applied only to objects some script names, so nothing can vanish for good.
	var named := _script_named_ids(idt)
	for o in objs:
		var d: Dictionary = o["data"]
		if d.get("script") == null or RomWorld.is_door(d): continue
		var oid := int(d.get("id", -1))
		if not named.has(oid): continue
		var w8 := int(d.get("w8", 0))
		var absent := w8 == 0 or (w8 >= 0x2000000 and (int(d.get("event", 0)) & 0x100) == 0)
		if absent: _set_obj_shown(oid, false)

var _named_ids := {}
var _named_done := false
func _script_named_ids(idt) -> Dictionary:
	## ids of every object some script (other than the system chunk that defines _id) refers to by name
	if _named_done: return _named_ids
	_named_done = true
	var names := {}
	var sys_id := EpfArc.crc32("/chunks/system.luc")
	for e in chunks.entries:
		if int(e["id"]) == sys_id: continue
		var fn = LuaVM.load_chunk(chunks.get_entry(e))
		if fn != null: _collect_names(fn.p, names)
	for n in names:
		var id = idt.get_v(n)
		if id != null and (id is int or id is float): _named_ids[int(id)] = true
	return _named_ids

func _collect_names(p, names: Dictionary) -> void:
	for k in p.consts:
		if k is String: names[k] = true
	for q in p.protos: _collect_names(q, names)

func _apply_cam() -> void:
	_layout()

func _layout() -> void:
	var win := get_viewport().get_visible_rect().size
	if ui_layer != null:
		var us := minf(win.x / VIEW.x, win.y / VIEW.y)
		if absf(us - _ui_built_scale) > 0.01:
			_ui_built_scale = us
			dialog.build(us, win); dev.build(us)
			if hud: hud.build(us, win)
		elif hud and hud.win != win: hud.build(us, win)
	var rs := room_size
	var sc: float
	if view_mode == 0: sc = minf(win.x / rs.x, win.y / rs.y)
	else: sc = maxf(win.x / rs.x, win.y / rs.y)
	scale = Vector2(sc, sc)
	var vis := win / sc    # visible room-space size
	if _center_cam:
		_center_cam = false
		cam = Vector2(maxf(rs.x - vis.x, 0.0), maxf(rs.y - vis.y, 0.0)) * 0.5
		if _cam_focus >= 0.0: cam.x = _cam_focus - vis.x * 0.5
		_cam_focus = -1.0
	if loop_x: cam.x = fposmod(cam.x, rs.x)
	else: cam.x = clampf(cam.x, 0.0, maxf(rs.x - vis.x, 0.0))
	cam.y = clampf(cam.y, 0.0, maxf(rs.y - vis.y, 0.0))
	var px := -cam.x * sc if (loop_x or rs.x * sc >= win.x) else (win.x - rs.x * sc) / 2.0
	if loop_x:
		for o in objs:
			var nx: Sprite2D = o["node"]
			nx.position.x = _wrap_x(float(o["bx"]), _obj_w(nx))
	var py := -cam.y * sc if rs.y * sc >= win.y else (win.y - rs.y * sc) / 2.0
	position = Vector2(px, py)
	for b in bg_nodes:
		var n: Sprite2D = b["node"]; var par: Vector2 = b["par"]
		var sz := Vector2(minf(vis.x, rs.x), minf(vis.y, rs.y)).ceil() + Vector2(1, 1)
		n.position = cam.floor()
		n.region_rect = Rect2((cam * par).floor(), sz)

func _input(e: InputEvent) -> void:
	if world == null: return                  # first-boot setup still running
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_TAB and hud and hud.visible:
		hud.toggle_top(); get_viewport().set_input_as_handled(); return
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F11:
		# F11: exclusive fullscreen (not a borderless window), and back to a window
		var fs := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		get_viewport().set_input_as_handled()

func _unhandled_input(e: InputEvent) -> void:
	if world == null: return                  # first-boot setup still running
	if iris != null and iris.busy(): return
	if minigame != null: return
	if _popup_wait: return
	if not api.input_enabled and not dialog.visible: return     # DisableInput (scripted scenes)
	if hud != null and hud.top_open and not dialog.visible: return   # the drop-down top screen covers the world
	if e is InputEventMouseButton and e.pressed and e.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		if hud and hud.dragging(): return
		if dialog.visible:
			if conv != null and conv.showing_options: return
			# DS sounds (DeSmuME): item pop-up closed 38; thought closed 38 + 2; NPC line advanced 2
			if dialog.item_rect != null and is_instance_valid(dialog.item_rect): sfx.play(Sfx.UI_BUTTON)
			elif dialog.kind == 1: sfx.play(Sfx.UI_BUTTON); sfx.play(Sfx.DLG_NEXT)
			else: sfx.play(Sfx.DLG_NEXT)
			if conv != null and conv.active: conv.click()
			else: dialog.advance()
			return
		var lp := get_local_mouse_position()
		if loop_x: lp.x = fposmod(lp.x, room_size.x)
		_touch_at(lp)

func _hit(o: Dictionary, p: Vector2) -> bool:
	var spr: Sprite2D = o["node"]
	var img: Image = o["dec"]["frames"][o["frame"]]["image"]
	var lp := p - spr.position
	if loop_x: lp.x = fposmod(lp.x, room_size.x)   # wrapped rooms re-place nodes near the camera; touches come in 0..width
	if RomWorld.is_door(o["data"]):
		# DS: a door/exit is touched anywhere inside its frame box, not just on opaque pixels (checked in DeSmuME).
		# Exits with no art (a 32x32 frame holding one anchor pixel) take a 64x64 box from the object's position.
		var ur := img.get_used_rect()
		var sz := Vector2(img.get_size())
		if ur.size.x <= 2 or ur.size.y <= 2: sz = Vector2(64, 64)
		return lp.x >= 0 and lp.y >= 0 and lp.x < sz.x and lp.y < sz.y
	# DS: objects and NPCs are touched anywhere in their sprite's bounds rectangle (RDT "bounds" = x, y, w, h), DeSmuME-checked
	var bd = o["dec"].get("bounds", null)
	if bd is Array and bd.size() == 4 and int(bd[2]) > 0 and int(bd[3]) > 0:
		return lp.x >= float(bd[0]) and lp.y >= float(bd[1]) and lp.x < float(bd[0]) + float(bd[2]) and lp.y < float(bd[1]) + float(bd[3])
	if lp.x < 0 or lp.y < 0 or lp.x >= img.get_width() or lp.y >= img.get_height(): return false
	return img.get_pixelv(Vector2i(lp)).a > 0.1

## ---- puffle commands (DeSmuME, M1C1 Snow Forts) ----
## Tap the puffle: BluePuffle_idle2ready -> _ready (cap on, juggling snowballs). Tap again: _ready2idle.
## While ready, tapping an object sends it ITEM_DROPPED with the puffle as source; if its script answers SetSuccess(self,
## true) the puffle plays _shoot and a _projectile snowball flies to it, _hit splashes there and the object gets COLLIDED
## (source = the puffle). Anything else (an NPC, empty ground) just gets _ready2idle.
var _puf_mode := ""               # "" idle/following, "ready", "busy"
var _proj: Sprite2D

func _puf_hit(p: Vector2) -> bool:
	if _puf == null or not is_instance_valid(_puf) or _puf.texture == null: return false
	var px := _puf_x
	if loop_x: px = cam.x + fposmod(_puf_x - cam.x, room_size.x)
	var q := p
	if loop_x: q.x = cam.x + fposmod(p.x - cam.x, room_size.x)
	return absf(q.x - px) <= 18.0 and q.y <= _puf_y + 2.0 and q.y >= _puf_y - 34.0

func _puf_play_once(k: String, next: String) -> void:
	_puf_set(k); _puf_after = next

func _puffle_tap(p: Vector2) -> bool:
	if _puf == null or not is_instance_valid(_puf): return false
	if _puf_mode == "busy": return true
	if _puf_mode == "":
		if not _puf_hit(p): return false
		_puf_mode = "busy"; _puf_ready_first = true; _puf_ammo = 3; _puf_play_once("BluePuffle_idle2ready", "BluePuffle_ready")
		return true
	if _puf_state != "BluePuffle_ready" and _puf_state != "BluePuffle_readyTO": return true   # mid-throw
	# ready
	if _puf_hit(p):
		_puf_mode = "busy"; _puf_play_once("BluePuffle_ready2idle", "BluePuffle"); return true
	var target = null
	for i in range(objs.size() - 1, -1, -1):
		var o: Dictionary = objs[i]
		if o["rt"] == null or not o["node"].visible or not _hit(o, p): continue
		target = o; break
	if target != null:
		sfx.play(Sfx.UI_TOUCH)
		var tid := int(target["data"]["id"])
		api.success_flags.erase(tid)
		var before := api.events.size()
		target["rt"].fire(api, "ITEM_DROPPED", api.puffle)
		_apply_events(before)
		if bool(api.success_flags.get(tid, false)):
			_puf_ammo -= 1
			_puf_play_once("BluePuffle_shoot", "BluePuffle_ready")
			_throw_snowball(target, p)
			return true
		# DS: an object that does not take the snowball (an NPC...) stands the puffle down
		_puf_mode = "busy"; _puf_play_once("BluePuffle_ready2idle", "BluePuffle")
		return true
	# DS: tapping the ground throws a snowball there; the puffle stays ready
	_puf_ammo -= 1
	_puf_play_once("BluePuffle_shoot", "BluePuffle_ready")
	_throw_snowball({}, p)
	return true

func _throw_snowball(target: Dictionary, p: Vector2) -> void:
	var a := _puf_anim("BluePuffle_projectile")
	if a.is_empty():
		if not target.is_empty(): _collide(target)
		return
	if _proj != null and is_instance_valid(_proj): _proj.queue_free()
	_proj = Sprite2D.new(); _proj.texture = a["tex"][0]; _proj.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	_proj.centered = false; _proj.z_index = 50
	_puf.get_parent().add_child(_proj)
	var px := _puf_x
	if loop_x: px = cam.x + fposmod(_puf_x - cam.x, room_size.x)
	var from: Vector2 = Vector2(px, _puf_y - 30.0) - a["center"]
	var to: Vector2 = p - a["center"]
	if loop_x: to.x = cam.x + fposmod(p.x - cam.x, room_size.x) - a["center"].x
	_proj.position = from; _proj.visible = false
	# DS: launched 25 frames after the tap (end of _shoot) with sound 156, lands 24 frames later with sound 57
	var tw := create_tween()
	tw.tween_interval(25.0 / 60.0)
	tw.tween_callback(func() -> void:
		if is_instance_valid(_proj): _proj.visible = true
		sfx.play(156)
		if _puf_ammo <= 0:
			# DS: out of snowballs - 2 frames after the last launch the puffle goes _ready2idle -> idle
			_puf_mode = "busy"; _puf_play_once("BluePuffle_ready2idle", "BluePuffle"))
	tw.tween_property(_proj, "position", to, 24.0 / 60.0)
	tw.tween_callback(func() -> void:
		sfx.play(57)
		var h := _puf_anim("BluePuffle_hit")
		if not h.is_empty() and is_instance_valid(_proj):
			_proj.texture = h["tex"][0]; _proj.position = to + a["center"] - h["center"]
		if not target.is_empty(): _collide(target)
		var tw2 := create_tween(); tw2.tween_interval(0.25)
		tw2.tween_callback(func() -> void:
			if is_instance_valid(_proj): _proj.queue_free()))

func _collide(target: Dictionary) -> void:
	if target.get("rt") == null: return
	var before := api.events.size()
	target["rt"].fire(api, "COLLIDED", api.puffle)
	_track_coroutines(target["rt"])
	var evs: Array = api.events.slice(before)
	_apply_events(before)
	_after_script_events(target["rt"], evs)

var _last_touch_win := Vector2(-1, -1)
func _touch_at(p: Vector2) -> void:
	if _puffle_tap(p): return
	_last_touch_win = p * scale + position
	if loop_x and _last_touch_win.x < 0.0: _last_touch_win.x += room_size.x * scale.x
	for m in model_touch:
		if m["rect"].has_point(p):
			_run_touch(m["name"], m["rt"], Vector2(m["rect"].position.x + m["rect"].size.x * 0.5, m["rect"].position.y) * scale + position, {}, int(m.get("id", -1)))
			return
	for i in range(objs.size() - 1, -1, -1):
		var o: Dictionary = objs[i]
		if (o["rt"] == null and not RomWorld.is_door(o["data"])) or not o["node"].visible or not _hit(o, p): continue
		if o["rt"] == null:
			if _try_exit(o["data"]): sfx.play(Sfx.DOOR)
			return                                   # plain door: no script, just the exit
		# DS: an unlocked exit just changes room; a door's script only speaks when the exit is locked (DeSmuME)
		if RomWorld.is_door(o["data"]) and not _exit_locked(o["data"]) and _try_exit(o["data"]):
			sfx.play(Sfx.DOOR); return
		sfx.play(Sfx.UI_TOUCH)
		var spr: Sprite2D = o["node"]
		var szi: Vector2 = o["dec"]["frames"][o["frame"]]["image"].get_size()
		_run_touch(str(o["data"]["name"]), o["rt"], (spr.position + Vector2(szi.x * 0.5, 0.0)) * scale + position, o["data"])
		return

## Fire TOUCHED on a script object and run whatever dialogue it queued (bubble above `head`, in window px).
func _run_touch(oname: String, rt, head: Vector2, odef: Dictionary = {}, oid: int = -1, reason := "TOUCHED", source := 0, quiet := false) -> void:
	var before := api.events.size()
	# ARM 0x210ad9c: an event with reason r only reaches the script if the object's interest mask has bit r (TOUCHED = bit 1).
	var tid := int(odef.get("id", oid)) if oid < 0 else oid
	if reason != "TOUCHED" or not strict_interest or int(api.interests.get(tid, 0)) & 2: rt.fire(api, reason, source)
	_track_coroutines(rt)
	var evs: Array = api.events.slice(before)
	_apply_events(before)
	if conv != null and conv.active: conv._close()
	conv = Conversation.new()
	var has_text := false
	for e in evs:
		if e["fn"] in ["AddDialog", "AddMonologue", "AddConversation", "AddLoopingConv"]: has_text = true
	if has_text:
		# DS: talking to an NPC (not a thought) first centres the camera on the speaker (Coffee Shop barista: cam 443 -> 515)
		var speaks := false
		for e in evs:
			if e["fn"] in ["AddDialog", "AddConversation", "AddLoopingConv"]: speaks = true
		dialog.speaker_feet = Vector2(-1, -1)
		if speaks and not odef.is_empty() and api.positions.has(tid):
			if _cam_before_talk < -1e8: _cam_before_talk = cam.x
			_pan_to(float(api.positions[tid].x))
			_talk_id = tid
			_set_talking(tid, true)
		conv.start(self, oname, rt, tid, head, evs)
		return
	if reason == "ITEM_DROPPED":
		if evs.is_empty(): _say_thought(275)
		return
	if reason == "COMBINE":
		if evs.is_empty(): _say_thought(190)
		return
	if _try_exit(odef): return
	if evs.is_empty() and not quiet: dialog.show_lines(oname, ["(" + oname + ")"], 2, head)   # dev: nothing scripted

var _pan_tw: Tween
var _talk_id := -1
var _cam_before_talk := -1e9      # camera x before an NPC conversation panned it; the DS pans back when the talk ends
func end_talk() -> void:
	if _talk_id >= 0: _set_talking(_talk_id, false)
	_talk_id = -1
	if _cam_before_talk > -1e8:
		var back := _cam_before_talk; _cam_before_talk = -1e9
		var vis := get_viewport().get_visible_rect().size / maxf(scale.x, 0.01)
		_pan_to(back + vis.x * 0.5)
## smooth camera pan so room x sits in the middle of the view
func _pan_to(x: float) -> void:
	var vis := get_viewport().get_visible_rect().size / maxf(scale.x, 0.01)
	var target := x - vis.x * 0.5
	if loop_x:
		var d := fposmod(target - cam.x + room_size.x * 0.5, room_size.x) - room_size.x * 0.5
		target = cam.x + d
	else:
		target = clampf(target, 0.0, maxf(room_size.x - vis.x, 0.0))
	if absf(target - cam.x) < 1.0: return
	if _pan_tw: _pan_tw.kill()
	_pan_tw = create_tween()
	_pan_tw.tween_method(func(v: float) -> void: cam.x = v; _layout(), cam.x, target, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Item pop-up: big item art + its SetItemPopUpText line (game strings). On pick-up the line is a thought.
## DisplayPopUp(GameStrings id, sprite): a picture with a thought line, like an item's zoom picture; the script
## waits on IsPopUpVisible until it is tapped away (hat penguin: the Groucho glasses, then the smiley).
## The DS layout of this popup has not been filmed; it is shown the same way as an item's zoom picture.
var _popup_open := false
func _display_popup(text_id: int, key: String) -> void:
	var dec := world.sprite(key)
	var line := game_text.get_text(text_id).replace("%", "").strip_edges()
	if conv != null and conv.active: conv._close()
	dialog.show_lines("", [line], 1)
	if not dec.is_empty() and not dec["frames"].is_empty():
		dialog.show_item(ImageTexture.create_from_image(dec["frames"][0]["image"]), Vector2(-1, -1))
	sfx.play(Sfx.ITEM_ZOOM)
	_popup_open = true

var _popup_wait := false          # an item's zoom picture is about to come up: taps wait
func _item_popup(id: int, picked: bool) -> void:
	var tid := int(api.popup_text.get(id, -1))
	var o: Dictionary = hud.item_defs.get(id, {})
	if tid < 0 and o.is_empty():
		api.popup_visible = false; return
	var line := game_text.get_text(tid).replace("%", "").strip_edges() if tid >= 0 else str(o.get("name", ""))
	if conv != null and conv.active: conv._close()
	# an item's zoom picture is a pop-up to the scripts: Dot (Dojo, M1C2) gives the pin, waits on IsPopUpVisible,
	# then says her next line
	api.popup_visible = true
	if picked:
		# DS (DeSmuME, M1C1 snowman's card): the giver's animation is seen for about 32 frames before the zoom
		# picture starts to come out of it. Measured on that one hand-over; other items are assumed to match.
		_popup_wait = true
		await get_tree().create_timer(32.0 / 60.0).timeout
		_popup_wait = false
	dialog.show_lines("", [line], 1)
	dialog.show_item(hud.item_zoom_tex(id), _last_touch_win if picked else Vector2(-1, -1))
	sfx.play(Sfx.ITEM_ZOOM)
	_popup_open = true

## room position (window px) -> room space, wrapping in looping rooms
func _win_to_room(p: Vector2) -> Vector2:
	var lp := (p - position) / scale
	if loop_x: lp.x = fposmod(lp.x, room_size.x)
	return lp

## Inventory item dropped on the room: ITEM_DROPPED (source = item) on the object under it.
func _on_item_dropped(item_id: int, win_pos: Vector2) -> void:
	var lp := _win_to_room(win_pos)
	for i in range(objs.size() - 1, -1, -1):
		var o: Dictionary = objs[i]
		if o["rt"] == null or not o["node"].visible or not _hit(o, lp): continue
		var spr: Sprite2D = o["node"]
		var szi: Vector2 = o["dec"]["frames"][o["frame"]]["image"].get_size()
		sfx.play(Sfx.UI_BUTTON); sfx.play(Sfx.ITEM_GIVE)   # DS: 38 then 48 when an item is dropped on an object
		_run_touch(str(o["data"]["name"]), o["rt"], (spr.position + Vector2(szi.x * 0.5, 0.0)) * scale + position, o["data"], -1, "ITEM_DROPPED", item_id)
		return
	_say_thought(275)      # "I am not sure what to do with this."

var item_rt: Dictionary = {}   # item id -> ObjectRuntime for inventory items with scripts (COMBINE)
## Item dragged onto another item: COMBINE (source = dragged item) on the target item's script.
func _on_items_combined(src: int, dst: int) -> void:
	var o: Dictionary = hud.item_defs.get(dst, {})
	if o.is_empty() or o.get("script") == null:
		_say_thought(190); return       # "These items do not seem to combine!"
	if not item_rt.has(dst):
		var cb := chunks.get_chunk(str(o["script"]).get_file().get_basename())
		if cb.is_empty(): _say_thought(190); return
		item_rt[dst] = ObjectRuntime.create({}, system_chunk, cb, api, dst, str(o["name"]))
	_run_touch(str(o["name"]), item_rt[dst], Vector2(-1, -1), o, dst, "COMBINE", src, true)

func _say_thought(game_string: int) -> void:
	if conv != null and conv.active: conv._close()
	dialog.show_lines("", [fmt(game_text.get_text(game_string))], 1)

## "Mission N: <name>" for the top screen. Story order: 1.01-1.03, 2.01-2.03, 3.01-3.03, 4.01-4.03, 5.01 = missions 1-13;
## game strings 191.. are the 13 mission names, 50.. are "MISSION 2:".."MISSION 13:" (there is no "MISSION 1:" string).
const STORY_ORDER := ["1.01", "1.02", "1.03", "2.01", "2.02", "2.03", "3.01", "3.02", "3.03", "4.01", "4.02", "4.03", "5.01"]
func _mission_line() -> String:
	var n := STORY_ORDER.find(mission) + 1
	if n <= 0: return ""
	var head := game_text.get_text(48 + n) if n >= 2 else game_text.get_text(74).strip_edges() + " 1:"
	return head.strip_edges() + " " + game_text.get_text(190 + n)

var model_touch: Array = []   # {name, rt, rect} room-space hit boxes for 3D objects

## 3D objects (e.g. SuperRobot*) are drawn into a small transparent SubViewport and shown as a sprite at the object position.
## The idle animation (if any) plays at 30 fps; frame meshes are built lazily and cached.
var talk_target := ""
var models3d: Array = []   # {md, anim, mi, cache, t, frame, foot}
func _add_model_object(o: Dictionary) -> void:
	var sd = o["sprite_dir"]
	if sd == null or not str(sd).to_lower().begins_with("3d/"): return
	var md := world.model(str(o["name"]))
	if md.is_empty(): return
	var model: Dictionary = md["model"]
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 256); vp.transparent_bg = true; vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam3 := Camera3D.new(); cam3.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam3.far = 1000.0
	vp.add_child(cam3)
	var mi := MeshInstance3D.new()
	vp.add_child(mi)
	add_child(vp)
	var spr := Sprite2D.new(); spr.centered = false; spr.texture = vp.get_texture()
	spr.position = Vector2(int(o["x"]) - 128, int(o["y"]) - 256 + model_yoff)
	add_child(spr)
	var anim := world.idle_animation(str(model["name"]), model["objects"].size())
	var entry := {"md": md, "anim": anim, "mi": mi, "cache": {}, "t": 0.0, "frame": -1, "foot": 0.0, "cam": cam3, "spr": spr, "vp": vp, "ox": int(o["x"]) - 128, "oy": int(o["y"]) - 256, "name": str(o["name"]), "id": int(o["id"]), "idle": anim, "talk": world.find_animation(str(model["name"]), "t", model["objects"].size()), "mode": "idle"}
	if not anim.is_empty():
		# keep the feet on the ground: shift by the lowest point of frame 0
		var d0 := EpfNsbmd.build_draws(model, EpfNsbca.object_matrices(anim, 0, model["objects"]))
		var lo := 1e9
		for d in d0:
			for v in d["verts"]: lo = minf(lo, v.y)
		entry["foot"] = lo
	models3d.append(entry)
	if o["script"] != null:
		var cb := chunks.get_chunk(str(o["script"]).get_file().get_basename())
		if not cb.is_empty():
			var rt := ObjectRuntime.create({}, system_chunk, cb, api, int(o["id"]), str(o["name"]))
			rt.fire(api, "CREATED")
			entry["hit"] = Rect2(Vector2(int(o["x"]) - 45, int(o["y"]) - 120), Vector2(90, 130))
			model_touch.append({"name": str(o["name"]), "id": int(o["id"]), "rt": rt, "rect": entry["hit"]})
	apply_model_tuning()
	_set_model_frame(entry, 0)

func _set_model_frame(e: Dictionary, f: int) -> void:
	var key := "%s:%d" % [e["mode"], f]
	if e["frame"] == f and e.get("key", "") == key: return
	e["frame"] = f; e["key"] = key
	if not e["cache"].has(key):
		var model: Dictionary = e["md"]["model"]
		var draws: Array = model["draws"]
		if not e["anim"].is_empty():
			draws = EpfNsbmd.build_draws(model, EpfNsbca.object_matrices(e["anim"], f, model["objects"]))
		var m2 := model.duplicate(); m2["draws"] = draws
		e["cache"][key] = EpfNsbmd.to_mesh(m2, e["md"]["textures"])["mesh"]
	e["mi"].mesh = e["cache"][key]
	e["mi"].position.y = -e["foot"] if not e["anim"].is_empty() else 0.0

func _process_models(dt: float) -> void:
	for e in models3d:
		var want: String = "talk" if (dialog.visible and talk_target == e["name"] and not e["talk"].is_empty()) else "idle"
		if want != e["mode"]:
			e["mode"] = want; e["anim"] = e[want]; e["t"] = 0.0; e["frame"] = -1
		if e["anim"].is_empty(): continue
		e["t"] += dt
		var f := int(e["t"] * 30.0) % int(e["anim"]["frames"])
		_set_model_frame(e, f)

## Called by the dev menu: model_scale = screen px per model unit, model_yoff = vertical nudge in px.
func apply_model_tuning() -> void:
	for e in models3d:
		var size := 256.0 / maxf(model_scale, 0.05)
		e["cam"].size = size
		e["cam"].position = Vector3(0, size / 2.0, 300)
		e["spr"].position = Vector2(e["ox"], e["oy"] + model_yoff)
		var k := 4 if model_hires else 1
		e["vp"].size = Vector2i(256 * k, 256 * k)
		e["vp"].msaa_3d = Viewport.MSAA_4X if model_hires else Viewport.MSAA_DISABLED
		e["spr"].scale = Vector2.ONE / float(k)
		e["spr"].texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if model_hires else CanvasItem.TEXTURE_FILTER_PARENT_NODE

func _load_bubble() -> void:
	dialog.font = EpfFont.load_font(world.fs, "fonts/bigUI.fnt") if world != null else null
	var names := {"chat": "npcChatBubble", "bottom": "npcChatBubbleBottom", "talk": "talktbubble", "thought": "thoughtbubble"}
	for k in names:
		var d: Dictionary = world.sprite("UI/ConversationSystem/" + names[k]) if world != null else {}
		if not d.is_empty() and d.has("frames") and d["frames"].size() > 0:
			dialog.bubbles[k] = ImageTexture.create_from_image(d["frames"][0]["image"])
	for bk in ["up", "down"]:
		var bd: Dictionary = world.sprite("UI/ConversationSystem/DialogButton_" + bk) if world != null else {}
		if not bd.is_empty() and bd.has("frames") and bd["frames"].size() > 0:
			if bk == "up": dialog.btn_up = ImageTexture.create_from_image(bd["frames"][0]["image"])
			else: dialog.btn_down = ImageTexture.create_from_image(bd["frames"][0]["image"])

# ---- original cursor: PC/Spryte/cursor (0 default) _touch2 (1 touchable) _door (2) _locked (3) _talk (4); ARM 0x20823b8 ----
var cursor_layer: CanvasLayer
var cursor_spr: Sprite2D
var cursor_tex: Dictionary = {}   # kind -> {tex, center}
var cursor_kind := -1
const CURSOR_KEYS := {0: "cursor", 1: "cursor_touch2", 2: "cursor_door", 3: "cursor_locked", 4: "cursor_talk"}

func _setup_cursor() -> void:
	for k in CURSOR_KEYS:
		var d: Dictionary = world.sprite("PC/Spryte/" + CURSOR_KEYS[k])
		if d.is_empty() or d["frames"].is_empty(): continue
		var c = d.get("center"); if c == null: c = [0, 0]
		cursor_tex[k] = {"tex": ImageTexture.create_from_image(d["frames"][0]["image"]), "center": Vector2(c[0], c[1])}
	if cursor_tex.is_empty(): rom_cursor = false; return
	cursor_layer = CanvasLayer.new(); cursor_layer.layer = 100; add_child(cursor_layer)
	cursor_spr = Sprite2D.new(); cursor_spr.centered = false
	cursor_spr.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	cursor_layer.add_child(cursor_spr)
	set_rom_cursor(rom_cursor)

func set_rom_cursor(on: bool) -> void:
	rom_cursor = on and not cursor_tex.is_empty()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if rom_cursor else Input.MOUSE_MODE_VISIBLE)
	if cursor_spr != null: cursor_spr.visible = rom_cursor

## Cursor from the object's interests (set by its script via AddInterest): 1 = door/exit, 2 and 5 = talk (NPC), 3 and 4 = touch/use/pick-up.
## A door whose exit is locked shows the locked cursor. (Mapping inferred from which scripts use which interest; the ARM selector is still to be located.)
## ARM 0x2112814: interest bit1 (mask&2) = touchable, bit2 (mask&4) = accepts dropped items.
## Door/talk/use is decided by the object itself (dest room / NPC sprite dir), not by the mask.
func _kind_for(id: int, fallback: int, has_dest := false) -> int:
	var mask := int(api.interests.get(id, 0))
	if has_dest and bool(api.exits_locked.get(id, _exit_default(id))): return 3
	if has_dest: return 2
	if not strict_interest or mask & 2: return fallback
	return 0

func _hover_kind(p: Vector2) -> int:
	for m in model_touch:
		if m["rect"].has_point(p): return _kind_for(int(m.get("id", 0)), 4)
	for i in range(objs.size() - 1, -1, -1):
		var o: Dictionary = objs[i]
		if (o["rt"] == null and not RomWorld.is_door(o["data"])) or not o["node"].visible or not _hit(o, p): continue
		var d: Dictionary = o["data"]
		var fb := 4 if str(d.get("sprite_dir", "")).begins_with("NPC/") else 1
		var dst = d.get("dest")
		return _kind_for(int(d.get("id", 0)), fb, dst != null and str(dst).to_lower() != "none")
	return 0

func _update_cursor() -> void:
	if not rom_cursor or cursor_spr == null: return
	var vp := get_viewport(); var mp := vp.get_mouse_position(); var win := vp.get_visible_rect().size
	## Dev menu open: use the normal OS cursor so the menu is easy to use.
	var want_os: bool = dev != null and dev.visible
	if want_os != _os_cursor:
		_os_cursor = want_os
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if want_os else Input.MOUSE_MODE_HIDDEN)
	if want_os:
		cursor_spr.visible = false; return
	cursor_spr.visible = Rect2(Vector2.ZERO, win).has_point(mp)
	var kind := 0 if dialog.visible or minigame != null or (hud != null and hud.top_open) else _hover_kind(get_local_mouse_position())
	if title != null: kind = 1 if title.hovering else 0
	elif menu != null: kind = 1 if menu.hovering else 0
	if kind != cursor_kind or not cursor_tex.has(kind):
		cursor_kind = kind
		var e: Dictionary = cursor_tex.get(kind, cursor_tex.get(0, {}))
		if not e.is_empty(): cursor_spr.texture = e["tex"]
	var us := minf(win.x / VIEW.x, win.y / VIEW.y) * cursor_mult
	var e2: Dictionary = cursor_tex.get(cursor_kind, cursor_tex.get(0, {}))
	if e2.is_empty(): return
	cursor_spr.scale = Vector2(us, us)
	cursor_spr.position = mp - e2["center"] * us

## Doors: if the touched object has a destination room, is not locked and its script queued no dialogue, travel there.
## Exit lock: the ROM's per-instance start value (object def word 10), changed by SetExitLocked and kept in the save.
func _exit_default(id: int) -> bool:
	for o in objs:
		if int(o["data"].get("id", -1)) == id: return int(o["data"].get("locked", 0)) != 0
	return false

func _exit_locked(odef: Dictionary) -> bool:
	var id := int(odef.get("id", 0))
	if api.exits_locked.has(id): return bool(api.exits_locked[id])
	return int(odef.get("locked", 0)) != 0

func _try_exit(odef: Dictionary) -> bool:
	var dest = odef.get("dest")
	if dest == null or str(dest).to_lower() == "none": return false
	if _exit_locked(odef): return false
	for r in world.room_prefixes():
		if str(r).to_lower() == str(dest).to_lower():
			if pending_exit.is_empty():
				pending_exit = {"room": str(r), "def": odef, "t": 0.0}
				for o in objs:
					if o["data"] == odef and o.has("door"): o["door"]["want"] = "open"
			return true
	return false

## ---- door states: <Door>_closed / _opening / _open / _closing (Location/<Room>/state/) ----
## The cursor over a door opens it (opening -> open), leaving it closes it (closing -> closed); a tap waits for it to be open,
## then changes room. Arrival: the door's w8 high half is the destination room's camera centre x.
var pending_exit: Dictionary = {}
var hover_door = null

func rdt_has(k: String) -> bool:
	return world.rdt.keys.has(k)

func _setup_door(o: Dictionary, base: String) -> void:
	var st := {}
	for n in ["closed", "opening", "open", "closing"]:
		var d: Dictionary = world.sprite(base + "_" + n)
		if d.is_empty() or d["frames"].is_empty(): continue
		var tx: Array = []; var du: Array = []; var ims: Array = []
		for f in d["frames"]:
			tx.append(ImageTexture.create_from_image(f["image"])); du.append(maxf(float(f["dur_ms"]), 16.0)); ims.append(f["image"])
		var cen = d.get("center"); if cen == null: cen = [0, 0]
		st[n] = {"tex": tx, "dur": du, "img": ims, "cen": Vector2(cen[0], cen[1])}
	if not st.has("closed"): return
	o["door"] = {"st": st, "state": "closed", "want": "closed", "i": 0, "t": 0.0}

func _door_set(o: Dictionary, n: String) -> void:
	var dd: Dictionary = o["door"]
	if not dd["st"].has(n): n = "open" if n == "opening" and dd["st"].has("open") else ("closed" if n == "closing" else n)
	if not dd["st"].has(n): return
	dd["state"] = n; dd["i"] = 0; dd["t"] = 0.0
	var s: Dictionary = dd["st"][n]
	var spr: Sprite2D = o["node"]
	spr.texture = s["tex"][0]
	spr.position = Vector2(int(o["data"]["x"]), int(o["data"]["y"])) - s["cen"]
	o["bx"] = spr.position.x
	if loop_x: spr.position.x = _wrap_x(float(o["bx"]), _obj_w(spr))
	# hit-testing follows the shown frame
	o["dec"] = {"frames": [], "center": [s["cen"].x, s["cen"].y]}
	for im in s["img"]: o["dec"]["frames"].append({"image": im, "dur_ms": 100})
	o["frame"] = 0

func _update_doors(dt: float) -> void:
	var hov = null
	if not dialog.visible and title == null and menu == null and (hud == null or (not hud.dragging() and not hud.top_open)):
		var lp := get_local_mouse_position()
		if loop_x: lp.x = fposmod(lp.x, room_size.x)
		for i in range(objs.size() - 1, -1, -1):
			var o: Dictionary = objs[i]
			if o["node"].visible and _hit(o, lp):
				if o.has("door") and not _exit_locked(o["data"]): hov = o      # a locked door stays shut
				break
	for o in objs:
		if not o.has("door"): continue
		var dd: Dictionary = o["door"]
		var want := "open" if (o == hov or (not pending_exit.is_empty() and pending_exit["def"] == o["data"])) else "closed"
		var stt: String = dd["state"]
		if want == "open" and stt in ["closed", "closing"]: _door_set(o, "opening")
		elif want == "closed" and stt in ["open", "opening"]: _door_set(o, "closing")
		var s: Dictionary = dd["st"][dd["state"]]
		dd["t"] += dt * 1000.0
		while dd["t"] >= s["dur"][dd["i"]]:
			dd["t"] -= s["dur"][dd["i"]]
			if dd["i"] + 1 < s["tex"].size(): dd["i"] += 1
			elif dd["state"] == "opening": _door_set(o, "open"); break
			elif dd["state"] == "closing": _door_set(o, "closed"); break
			else: dd["i"] = 0
			o["node"].texture = s["tex"][dd["i"]]; o["frame"] = dd["i"]
	if not pending_exit.is_empty():
		pending_exit["t"] += dt
		var ready: bool = pending_exit["t"] > 0.9
		for o in objs:
			if o["data"] == pending_exit["def"]:
				ready = ready or not o.has("door") or o["door"]["state"] == "open"
		if ready:
			var pe: Dictionary = pending_exit; pending_exit = {}
			if str(pe["room"]) == "LevelSelect":
				open_map()                 # a door to LEVELSELECT (the Dojo's) leads out to the island map
			elif iris != null and iris_wipe:
				_iris_exit = pe
				iris.px_scale = maxf(scale.x, 0.01); iris.close()
			else:
				_change_room(pe)

## The iris has covered the screen: swap rooms underneath, then let it open.
func _on_iris_closed() -> void:
	if not _iris_exit.is_empty():
		var pe := _iris_exit; _iris_exit = {}
		_change_room(pe)
	iris.room_ready()

func _change_room(pe: Dictionary) -> void:
	if true:
			var from_room := room_prefix
			_room_focus = -1.0
			load_room(pe["room"])
			var ax := int(pe["def"].get("w8", 0)) >> 16
			if _room_focus >= 0.0:
				# the room script's SetCursorPos wins over the door's arrival camera (DS: Snow Forts M1C1 centres the snowman)
				var win0 := get_viewport().get_visible_rect().size
				cam.x = _room_focus - (win0.x / maxf(scale.x, 0.01)) * 0.5; cam.y = 0.0
				_center_cam = false; _layout()
			elif ax > 0 and ax < int(room_size.x) + 400:
				var win := get_viewport().get_visible_rect().size
				cam.x = float(ax) - (win.x / maxf(scale.x, 0.01)) * 0.5; cam.y = 0.0
				_center_cam = false; _layout()
			else:
				_center_on_door_to(from_room)
			_puf_snap()

## Heuristic (original arrival logic not decoded): centre the camera on the door of the new room that leads back to `from_room`.
func _center_on_door_to(from_room: String) -> void:
	var win := get_viewport().get_visible_rect().size
	var sc := maxf(scale.x, 0.01)
	for o in objs:
		var d = o["data"].get("dest")
		if d != null and str(d).to_lower() == from_room.to_lower():
			cam.x = float(o["node"].position.x) - (win.x / sc) * 0.5
			cam.y = 0.0
			_layout()
			return

## Apply the object-state calls a script made (events queued by GameApi from index `from`): DelItem/SetSpawn/SetVisible/AddItem change what is drawn.
## Object ids come from the call (second/first arg) or the running script's own object.
func _apply_events(from: int) -> void:
	for e in api.events.slice(from):
		var a: Array = e["args"]
		var fn: String = e["fn"]
		var id := int(e["self"])
		match fn:
			"DelItem": _set_obj_shown(int(a[0]) if a.size() > 0 else id, false); world_shown[int(a[0]) if a.size() > 0 else id] = false
			"AddItem": _set_obj_shown(int(a[0]) if a.size() > 0 else id, true); world_shown[int(a[0]) if a.size() > 0 else id] = true
			"AddInventoryItem":
				sfx.play(Sfx.ITEM_GET)
				hud.set_items(api.inventory)
				if a.size() > 0: _item_popup(int(a[0]), true)
			"RemoveInventoryItem": hud.set_items(api.inventory)
			"DisplayPopUp": if a.size() > 1: _display_popup(int(a[0]), str(a[1]))
			"PlaySFX": if a.size() > 0: sfx.play(int(a[0]))
			"StartMiniGame": if a.size() > 0: start_script_minigame.call_deferred(int(a[0]), int(a[1]) if a.size() > 1 else 0)
			"EndMission": end_mission.call_deferred()
			"SetObjective": if a.size() > 0: objective_id = int(a[0]); _show_objective_id()
			"SetPuffle":
				hud.puffle_item = api.puffle; hud.refresh()
				_show_room_puffle()
			"HideMap": hud.map_enabled = false; hud.refresh()
			"ShowMap": hud.map_enabled = true; hud.refresh()
			"SetCursorPos": if a.size() > 0: _cam_focus = float(a[0]); _room_focus = float(a[0])
			"StartMission": if a.size() > 0: start_mission.call_deferred(int(a[0]))
			"ActivateNpc":                   # ActivateNpc(id, n): reveal the NPC, set its conversation to n and start it
				if a.size() > 0:
					# DS: an activated NPC is brought into view (Snow Forts M1C1: camera centred on the snowman, no SetCursorPos)
					if _room_focus < 0.0 and api.positions.has(int(a[0])):
						_room_focus = float(api.positions[int(a[0])].x); _cam_focus = _room_focus
					_set_obj_shown(int(a[0]), true); world_shown[int(a[0])] = true
					if a.size() > 1: api.conv_counts[int(a[0])] = int(a[1])
					pending_npc = int(a[0])
			"SetVisible":
				var tid := int(a[1]) if a.size() > 1 and int(a[1]) > 0 else id
				_set_obj_shown(tid, bool(a[0]) if a.size() > 0 else true); world_shown[tid] = bool(a[0]) if a.size() > 0 else true
			"SetSpawn":
				# DS: SetSpawn decides whether the object is there when its room is next entered; while a room is loading
				# that is now. Mid-room it changes nothing on screen (Snow Forts M1C1: the snowman stays after SetSpawn(0)).
				var sid := int(a[1]) if a.size() > 1 and int(a[1]) > 0 else id
				if _loading_room: _set_obj_shown(sid, bool(a[0]) if a.size() > 0 else true)
				world_shown[sid] = bool(a[0]) if a.size() > 0 else true
			"SwitchState":                   # SwitchState(state[, obj]): play the object's <sprite>_<state> animation
				_switch_state(int(a[1]) if a.size() > 1 and int(a[1]) > 0 else id, str(a[0]) if a.size() > 0 else "")
			"PushCamera":
				if _cam_stack.size() < 8: _cam_stack.append(cam.x)
				var pid2 := int(a[0]) if a.size() > 0 else id
				if api.positions.has(pid2): _pan_to(float(api.positions[pid2].x))
			"PopCamera":
				if not _cam_stack.is_empty():
					var back: float = _cam_stack.pop_back()
					var vis2 := get_viewport().get_visible_rect().size / maxf(scale.x, 0.01)
					_pan_to(back + vis2.x * 0.5)

var _loading_room := false
var _cam_stack: Array = []
var _co_rts: Array = []          # runtimes with coroutines still running (scriptPlay)

## SwitchState: swap the object's sprite to <base>_<state> (NPC/Dot/DotSnowPenguinPostcard_give ...); IsAnimPlaying is true
## until a non-looping state animation reaches its last frame.
func _switch_state(oid: int, state: String) -> void:
	for o in objs:
		if int(o["data"].get("id", -1)) != oid or o.has("door"): continue
		var base := str(o.get("base_key", world._key_for(o["data"])))
		o["base_key"] = base
		var key := base if state == "" else base + "_" + state
		o.erase("pre_talk")                       # a scripted state change wins over the talk animation
		var dec := world.sprite(key)
		if dec.is_empty() or dec["frames"].is_empty():
			api.anim_playing[oid] = false; return
		var tex: Array = []
		for f in dec["frames"]: tex.append(ImageTexture.create_from_image(f["image"]))
		var cen = dec.get("center"); if cen == null: cen = [0, 0]
		var spr: Sprite2D = o["node"]
		var anchor: Vector2 = api.positions.get(oid, spr.position)
		spr.position = Vector2(anchor.x - int(cen[0]), anchor.y - int(cen[1])); o["bx"] = spr.position.x
		o["dec"] = dec; o["tex"] = tex; o["frame"] = 0; o["t"] = 0.0; o["cur_key"] = key
		var lpv = dec.get("looping", 1)
		o["state_once"] = lpv != null and (str(lpv) == "0" or str(lpv) == "false")
		# An animation with no looping property (SnowFortsNPC1hat_give, the _TO fidgets) plays once and the object
		# goes back to its idle animation, which has looping = 1. DS, M1C1: after handing over the glasses the hat
		# penguin is in his normal pose again though his script never switches him back.
		o["state_revert"] = state != "" and lpv == null and tex.size() > 1
		spr.texture = tex[0]
		api.anim_playing[oid] = o["state_once"] and tex.size() > 1
		return

func _obj_by_id(oid: int) -> Dictionary:
	for o in objs:
		if int(o["data"].get("id", -1)) == oid and not o.has("door"): return o
	return {}

## DS: an NPC plays its _talk animation for as long as you are in conversation with it (its line and the reply options;
## DeSmuME, M1C1 Coffee Shop: BaristaCup -> BaristaCup_talk), and goes back to what it was doing when the talk ends or
## turns into the player's thought. The talk anim is the current animation's own _talk (BaristaCup_talk), else the
## character's base one (Barista_talk).
func _set_talking(oid: int, on: bool) -> void:
	if _puf_trace: print("TALK ", oid, " ", on)
	for o in objs:
		if int(o["data"].get("id", -1)) != oid or o.has("door") or not o.has("tex"): continue
		if on:
			if o.has("pre_talk"): return
			if o.get("state_revert", false): _switch_state(oid, ""); o = _obj_by_id(oid)
			var base := str(o.get("base_key", world._key_for(o["data"])))
			var cur := str(o.get("cur_key", base))
			var key := cur + "_talk"
			if not rdt_has(key): key = base + "_talk"
			if not rdt_has(key): return
			var dec := world.sprite(key)
			if dec.is_empty() or dec["frames"].is_empty(): return
			o["pre_talk"] = {"dec": o["dec"], "tex": o["tex"], "frame": o["frame"], "state_once": o.get("state_once", false), "pos": o["node"].position, "bx": o.get("bx", o["node"].position.x)}
			var tex: Array = []
			for f in dec["frames"]: tex.append(ImageTexture.create_from_image(f["image"]))
			var cen = dec.get("center"); if cen == null: cen = [0, 0]
			var spr: Sprite2D = o["node"]
			var anchor: Vector2 = api.positions.get(oid, spr.position)
			spr.position = Vector2(anchor.x - int(cen[0]), anchor.y - int(cen[1])); o["bx"] = spr.position.x
			o["dec"] = dec; o["tex"] = tex; o["frame"] = 0; o["t"] = 0.0; o["state_once"] = false
			spr.texture = tex[0]
			if _puf_trace: print("TALKANIM ", key, " frames ", tex.size())
		elif o.has("pre_talk"):
			var pt: Dictionary = o["pre_talk"]; o.erase("pre_talk")
			o["dec"] = pt["dec"]; o["tex"] = pt["tex"]; o["frame"] = pt["frame"]; o["t"] = 0.0; o["state_once"] = pt["state_once"]
			o["node"].position = pt["pos"]; o["bx"] = pt["bx"]
			o["node"].texture = o["tex"][o["frame"]]
		return

## Lua coroutines started with scriptPlay are resumed once per frame (system.luc runCoroutines), and whatever they
## queue is applied as it happens - so scripted scenes play out over time instead of all at once.
func _track_coroutines(rt) -> void:
	if rt != null and not _co_rts.has(rt): _co_rts.append(rt)

func _pump_coroutines() -> void:
	if _co_rts.is_empty(): return
	for rt in _co_rts.duplicate():
		var cos = rt.vm.G.get_v("_coroutines")
		var n := 0
		if cos is LuaVM.LuaTable: n = cos.length()
		if n == 0: _co_rts.erase(rt); continue
		var before := api.events.size()
		api.current_self = rt.obj_id
		var rc = rt.vm.G.get_v("runCoroutines")
		if rc != null: rt.vm.call_fn(rc, [])
		if api.events.size() > before:
			var evs: Array = api.events.slice(before)
			_apply_events(before)
			_after_script_events(rt, evs)

## dialogue queued from inside a running scripted scene starts a conversation like a touch would
func _after_script_events(rt, evs: Array) -> void:
	for e in evs:
		if e["fn"] in ["AddDialog", "AddMonologue", "AddConversation", "AddLoopingConv"]:
			if conv != null and conv.active and dialog.visible: return
			if conv != null and conv.active: conv._close()      # a talk left open with nothing on screen
			conv = Conversation.new()
			conv.start(self, rt.name, rt, rt.obj_id, Vector2(-1, -1), evs)
			return

## ---- what scripts changed in the world stays changed ----
## The room scripts' CREATED handlers only re-add interests on re-entry (SnowForts M1C1: nothing restores the hat
## trade), so the engine itself keeps which objects scripts showed or hid (AddItem / DelItem / ActivateNpc /
## SetVisible / SetSpawn) and each object's last SwitchState, and re-applies them whenever a room loads. Saved too.
var world_shown: Dictionary = {}     # object id -> shown
func _restore_world_state() -> void:
	var here := {}
	for o in objs: here[int(o["data"].get("id", -1))] = true
	for id in world_shown:
		if here.has(int(id)): _set_obj_shown(int(id), bool(world_shown[id]))
	for id in api.states:
		if not here.has(int(id)): continue
		_switch_state(int(id), str(api.states[id]))
		for o in objs:     # a one-shot state (a hat falling) is already over: show its last frame
			if int(o["data"].get("id", -1)) == int(id) and o.get("state_once", false) and o["tex"].size() > 0:
				o["frame"] = o["tex"].size() - 1; o["node"].texture = o["tex"][o["frame"]]; o["done"] = true
				api.anim_playing[int(id)] = false

func _set_obj_shown(id: int, shown: bool) -> void:
	for o in objs:
		if int(o["data"].get("id", -1)) == id:
			o["node"].visible = shown
			o["shown"] = shown
	for m in models3d:
		if int(m.get("id", -2)) == id:
			m["spr"].visible = shown
