extends SceneTree
func _init() -> void:
	var w := RomWorld.open(ProjectSettings.globalize_path("res://game.epf"))
	w.set_lang("en")
	for n in ["MapPiece1_up", "MapPiece2_up", "MapPiece3_up", "MapPiece4_up", "rotateHandle", "rotateCursor"]:
		var dec = w.sprite("Microgames/Jigsaw/" + n)
		if dec == null or dec["frames"].is_empty(): print("NONE ", n); continue
		var f: Dictionary = dec["frames"][0]
		var im: Image = f["image"]
		print("SPR ", n, " size ", im.get_size(), " used ", im.get_used_rect(), " frames ", dec["frames"].size(), " keys ", f.keys())
		im.save_png("/tmp/claude-0/jig_%s.png" % n)
	var bg := EpfNbfc.load_bg(w, "bg/Microgames/Jigsaw/Jigsaw_bottom")
	if bg: bg.save_png("/tmp/claude-0/jig_bottom.png"); print("BG ", bg.get_size())
	quit()
