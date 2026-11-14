extends SceneTree
## Port-side twin of /tmp/emu/play.py: drive the game with a list of actions and save screenshots.
## args: <out_prefix> actions...
##   mission:1.01  room:CoffeeShop0  touch:<object name>  tap:x,y (DS px in the room view)  click (advance dialogue)
##   wait:<seconds>  shot  log (print dialog/objective/inventory/vars)  load:<save json>  save:<path>  story (new game)
var m
var _evmark := 0
var _mark := 0

func _init() -> void:
	m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._set_lang("en")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out := args[0]
	var shots: Array = []
	for a in args.slice(1):
		var k := a.get_slice(":", 0); var v := a.substr(k.length() + 1)
		if OS.get_environment("PPLAY_TRACE") != "": print("ACT ", a)
		var _ev0: int = m.api.events.size()
		match k:
			"story":
				m._show_menu(); await create_timer(0.2).timeout
				m.menu.player_color = "lime"; m.hud.player_doll = m.menu.doll_image(); m.menu.queue_free(); m.menu = null
				m._new_story(); await create_timer(0.5).timeout
			"mission": m.set_mission(v); await create_timer(0.3).timeout
			"continue":   # load the save the way Continue on the main menu does
				m._show_menu(); await create_timer(0.2).timeout
				m._on_start_game(false); await create_timer(1.0).timeout
			"quit":   # what closing the window does
				m._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
			"start": m.start_mission(int(v)); await create_timer(0.3).timeout
			"room":
				m.load_room(v); await create_timer(0.3).timeout
			"touch":
				var t = null
				for o in m.objs:
					if str(o["data"]["name"]) == v and o["node"].visible: t = o
				if t == null: print("NOOBJ ", v)
				else:
					var img: Image = t["dec"]["frames"][t["frame"]]["image"]
					var ur := img.get_used_rect()
					var pt: Vector2 = t["node"].position + Vector2(ur.position) + Vector2(ur.size) * 0.5
					if RomWorld.is_door(t["data"]) and (ur.size.x <= 2 or ur.size.y <= 2): pt = t["node"].position + Vector2(32, 32)
					if m.loop_x: pt.x = fposmod(pt.x, m.room_size.x)
					if OS.get_environment("PPLAY_TRACE") != "":
						var hitl := []
						for o2 in m.objs:
							if o2["node"].visible and m._hit(o2, pt): hitl.append(str(o2["data"]["id"]) + ":" + str(o2["data"]["name"]))
						print("TOUCH ", v, " at ", pt, " hits ", hitl)
					m._touch_at(pt)
				await create_timer(0.4).timeout
			"drop":   # drop:<item id or _id name>:<object name>
				var iid := _item_id(v.get_slice(":", 0)); var on := v.get_slice(":", 1)
				for o in m.objs:
					if str(o["data"]["name"]) == on and o["node"].visible:
						var bd = o["dec"].get("bounds", [0, 0, 8, 8])
						var rp: Vector2 = o["node"].position + Vector2(bd[0] + bd[2] * 0.5, bd[1] + bd[3] * 0.5)
						m._on_item_dropped(iid, rp * m.scale + m.position)
						break
				await create_timer(0.6).timeout
			"tappuf":
				var px: float = m._puf_x
				if m.loop_x: px = m.cam.x + fposmod(m._puf_x - m.cam.x, m.room_size.x)
				m._touch_at(Vector2(px, m._puf_y - 12.0)); await create_timer(0.6).timeout
			"touchid":
				for o in m.objs:
					if int(o["data"]["id"]) == int(v) and o["node"].visible:
						var bd = o["dec"].get("bounds", [0, 0, 8, 8])
						var rp: Vector2 = o["node"].position + Vector2(bd[0] + bd[2] * 0.5, bd[1] + bd[3] * 0.5)
						if m.loop_x: rp.x = fposmod(rp.x, m.room_size.x)
						m._touch_at(rp); break
				await create_timer(0.4).timeout
			"tapr":   # tapr:x,y = room px relative to the camera's left edge
				m._touch_at(Vector2(m.cam.x + float(v.get_slice(",", 0)), float(v.get_slice(",", 1))))
				await create_timer(0.4).timeout
			"tapcut":   # tap during a cutscene
				if m.cutscene != null: m.cutscene._end()
				await create_timer(0.1).timeout
			"camx":   # camx:+N scrolls the camera by N room px
				m._center_cam = false; m.cam.x += float(v); m._layout()
				await create_timer(0.05).timeout
			"adv":   # like a tap on the DS: picks reply v (default 0) when choices are up, else advances
				if m.dialog.opt_nodes.size() > 0: m.dialog.pick_option(int(v) if v.is_valid_int() else 0)
				else: m._unhandled_input(_tap(true)); m._unhandled_input(_tap(false))
				await create_timer(0.35).timeout
			"click":
				var ev := InputEventMouseButton.new(); ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true
				ev.position = m.get_viewport().get_visible_rect().size * 0.5
				var ov = null
				for c in m.get_children():
					if c.has_method("_next") and c.get("pics") != null: ov = c
				if ov != null: ov._input(ev)          # full-screen layers (outro pictures) take the tap first
				else: m._unhandled_input(ev)
				await create_timer(0.35).timeout
			"opt":
				print("OPT nodes=", m.dialog.opt_nodes.size(), " conv=", m.conv != null and m.conv.active, " showing=", m.conv.showing_options if m.conv != null else null)
				if m.dialog.has_method("pick_option"): m.dialog.pick_option(int(v))
				elif m.conv != null: m.conv.choose(int(v))
				await create_timer(0.35).timeout
			"talk":   # advance the current conversation to its end: first option at each choice (talk:N picks option N)
				var pick := int(v) if v.is_valid_int() else 0
				for _i in 40:
					await create_timer(0.3).timeout
					if not m.dialog.visible and (m.conv == null or not m.conv.active): break
					if m.conv != null and m.conv.active and m.conv.showing_options:
						if OS.get_environment("PPLAY_TRACE") != "": print("TALK opt ", pick)
						m.dialog.pick_option(mini(pick, m.dialog.opt_nodes.size() - 1))
					else:
						var ev2 := InputEventMouseButton.new(); ev2.button_index = MOUSE_BUTTON_LEFT; ev2.pressed = true
						ev2.position = m.get_viewport().get_visible_rect().size * 0.5
						m._unhandled_input(ev2)
				await create_timer(0.4).timeout
			"savegame": m._write_save(); await create_timer(0.1).timeout
			"reload":   # quit and continue: forget everything in memory, then load the save like Continue does
				m.api.vars = {}; m.api.inventory.clear(); m.api.states.clear(); m.api.conv_counts.clear()
				m.world_shown.clear(); m.api.exits_locked.clear(); m.api.suitcase_enabled.clear()
				m._on_start_game(false); await create_timer(1.5).timeout
			"wait": await create_timer(float(v)).timeout
			"shot":
				await process_frame
				shots.append(root.get_texture().get_image())
			"log":
				await create_timer(0.4).timeout
				_log()
			"jigsolve":   # put every jigsaw piece on its target the way a player would (move, turn, release)
				var j = m.minigame
				if j == null or not j.has_method("_try_snap"): print("NOJIG")
				else:
					for i in j.pieces.size():
						j.pieces[i]["pos"] = j.pieces[i]["target"] + Vector2(3, -2); j.pieces[i]["rot"] = 0.0
						j._try_snap(i)
					j._draw_all()
				await create_timer(1.6).timeout
			"talkuntiloutro":   # click / pick option 0 until a chapter outro is on screen (max N rounds)
				for r in int(v):
					var found := false
					for c in m.get_children():
						if c.has_method("_next") and c.get("pics") != null: found = true
					if found: break
					var ev2 := InputEventMouseButton.new(); ev2.button_index = MOUSE_BUTTON_LEFT; ev2.pressed = true
					ev2.position = m.get_viewport().get_visible_rect().size * 0.5
					m._unhandled_input(ev2)
					await create_timer(0.25).timeout
					if m.dialog.has_method("pick_option"): m.dialog.pick_option(0)
					elif m.conv != null: m.conv.choose(0)
					await create_timer(0.25).timeout
				await create_timer(1.2).timeout
			"convs": print("CONVS ", m.api.conv_counts)
			"shown": print("SHOWN ", m.world_shown)
			"hudinfo": print("HUD map_enabled=", m.hud.map_enabled, " api.map=", m.api.map_shown, " vis=", m.hud.visible, " inv=", m.api.inventory.keys(), " suit=", m.api.suitcase_enabled)
			"map": m.open_map(); await create_timer(0.5).timeout
			"mappad":   # tap a place on the open map
				var ms = m.minigame
				if ms == null or not ms.has_method("_go"): print("NOMAP")
				elif ms.cur == v: ms._enter()
				else: ms._go(v)
			"mdown", "mup", "mmove":   # raw mouse in window px
				var xy := v.split(",")
				var pos := Vector2(float(xy[0]), float(xy[1]))
				if k == "mmove":
					var mm := InputEventMouseMotion.new(); mm.position = pos; mm.global_position = pos; Input.parse_input_event(mm)
				else:
					var mb := InputEventMouseButton.new(); mb.button_index = MOUSE_BUTTON_LEFT; mb.pressed = k == "mdown"
					mb.position = pos; mb.global_position = pos; Input.parse_input_event(mb)
				await create_timer(0.05).timeout
			"mapjit":   # per-frame scroll steps in screen px while edge scrolling
				var st := []
				var last: float = m.minigame.scroll.position.x * m.minigame.root.scale.x
				for i in 40:
					await process_frame
					var now: float = m.minigame.scroll.position.x * m.minigame.root.scale.x
					st.append(snappedf(last - now, 0.01)); last = now
				print("MAPJIT ", st)
			"mapcam": print("MAPCAM ", m.minigame.cam, " pen=", m.minigame._pen_pos, " follow=", m.minigame._follow, " held=", m.minigame._held, " win=", root.size)
			"mapinfo":
				var ms2 = m.minigame
				print("MAP color=", m.player_color, " remap=", (ms2._remap.size() if ms2 != null else -1), " cur=", ms2.cur if ms2 != null and "cur" in ms2 else null, " level=", m.map_level, " alerts=", m.api.map_alerts, " rooms=", m._stage_rooms())
			"exits":   # exit lock state for the room's doors
				print("ELOCKS ", m.api.exits_locked)
				for o in m.objs:
					if o.has("door") or RomWorld.is_door(o["data"]): print("EXIT ", o["data"]["name"], " id=", o["data"]["id"], " locked=", m._exit_locked(o["data"]))
			"evmark": _evmark = m.api.events.size()
			"events":   # API calls since the last evmark (no dialogue text)
				for e in m.api.events.slice(_evmark):
					var ea: Array = []
					for x in e.get("args", []): ea.append(x if not (x is String and x.length() > 24) else "<text>")
					print("EV ", e["fn"], " ", ea)
				_evmark = m.api.events.size()
			"objs":   # visible objects with their state
				for o in m.objs:
					if o["node"].visible: print("OBJ ", o["data"]["name"], " state=", o.get("state", ""), " id=", o["data"]["id"])
			"mark": _mark = m.api.events.size()
			"setconv":   # setconv:<obj id>:<count>
				m.api.conv_counts[int(v.get_slice(":", 0))] = int(v.get_slice(":", 1))
			"consts":
				for o in m.objs:
					if o["rt"] != null:
						var c = o["rt"].vm.G.get_v("_const")
						for ck in ["CHANGE_DIALOG", "END_DIALOG", "CHANGE_NPC", "CHANGE_ROOM", "END_MISSION", "UPDATE_LOOP", "PLAY_CUTSCENE"]:
							print("CONST ", ck, " ", c.get_v(ck))
						break
			"loadevs":   # the script calls made while the current room loaded (CREATED + room script)
				for e in m.dbg_events:
					if true:
						var a3: Array = []
						for x in e["args"]: a3.append(x if (x is int or x is float) else "<str>")
						print("LOADEV ", e["fn"], " ", a3)
			"objs":   # list objects whose name contains v: id, name, visible, state
				for o in m.objs:
					if v == "" or str(o["data"]["name"]).contains(v):
						print("OBJ ", o["data"]["id"], " ", o["data"]["name"], " vis=", o["node"].visible, " state=", m.api.states.get(int(o["data"]["id"]), ""), " interest=", m.api.interests.get(int(o["data"]["id"]), "-"), " rt=", o["rt"] != null)
			"evs":   # script calls since the last mark: name + numeric args (text left out)
				for e in m.api.events.slice(_mark):
					var a2: Array = []
					for x in e["args"]: a2.append(x if (x is int or x is float) else ("<str>" if x is String else typeof(x)))
					print("EV ", e.get("self_id", "?"), " ", e["fn"], " ", a2)
				_mark = m.api.events.size()
	await process_frame
	shots.append(root.get_texture().get_image())
	var w: int = shots[0].get_width() / 2; var h: int = shots[0].get_height() / 2
	var sheet := Image.create(w * mini(shots.size(), 4), h * int(ceil(shots.size() / 4.0)), false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var s: Image = shots[i]; s.resize(w, h)
		s.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(s, Rect2i(0, 0, w, h), Vector2i((i % 4) * w, (i / 4) * h))
	sheet.save_png(out + ".png")
	_log()
	quit()

## numeric id, or a name from the scripts' _id table (Inventory_PuffleBlue)
func _tap(down: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new(); ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = down
	ev.position = m.get_viewport().get_visible_rect().size * 0.5
	return ev

func _item_id(t: String) -> int:
	if t.is_valid_int(): return int(t)
	for o in m.objs:
		if o["rt"] != null:
			var idt = o["rt"].vm.G.get_v("_id")
			if idt != null and idt.get_v(t) != null: return int(idt.get_v(t))
	print("NOID ", t); return -1

func _log() -> void:
	print("ROOM ", m.room_prefix, " MISSION ", m.mission, " OBJ ", m.hud.objective if m.hud else "", " INV ", m.api.inventory.keys(), " PUFFLE ", m.api.puffle)
	print("VARS ", m.api.vars)
	print("INPUT ", m.api.input_enabled, " ANIM ", m.api.anim_playing, " CO ", m._co_rts.size(), " CONVPOS ", (str(m.conv.pos) + "/" + str(m.conv.items.size()) + " opt " + str(m.conv.showing_options) + " after " + str(not m.conv._after_reply.is_null())) if m.conv != null else "-")
	print("DIALOG ", m.dialog.visible, " CAM ", m.cam, " conv ", m.conv != null and m.conv.active, " PUF ", m._puf_state, " ", m._puf_mode, " x ", m._puf_x)
