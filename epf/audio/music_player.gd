class_name MusicPlayer
extends Node
## Plays EpfMusic through an AudioStreamGenerator. Mixing runs on a worker thread.
## Loads everything from the ROM at runtime: sound/music.bin + overlay 0.

var eng: EpfMusic
var room_defaults: Dictionary = {}
var room_over: Dictionary = {}
var player: AudioStreamPlayer
var gen: AudioStreamGenerator
var pb: AudioStreamGeneratorPlayback
var thread: Thread
var pre_thread: Thread
var mtx := Mutex.new()
var running := false
var want_song := -1          # request from main thread (-2 = stop)
var cur_song := -1
var volume := 0.8
var muted := false
var interp := false          # false = nearest (DS SPU behaviour)
var carry := 0.0             # seconds of audio until next sequencer tick
var ready_ok := false

func setup(rom: NdsRom, music_bin: PackedByteArray) -> bool:
	var ov := rom.overlay_data(0)
	if music_bin.size() < 64 or ov.size() < 1000: return false
	eng = EpfMusic.open(music_bin, ov)
	var t := eng.room_song_table()
	room_defaults = t["default"]; room_over = t["over"]
	gen = AudioStreamGenerator.new()
	gen.mix_rate = EpfMusic.MIX_RATE
	gen.buffer_length = 0.25
	player = AudioStreamPlayer.new()
	player.stream = gen
	add_child(player)
	player.play()
	pb = player.get_stream_playback()
	running = true
	thread = Thread.new()
	thread.start(_run)
	pre_thread = Thread.new(); pre_thread.start(eng.preload_all)
	ready_ok = true
	return true

func song_for_room(room: String, chapter := -1, sub := -1) -> int:
	room = room.to_upper()
	var k := "%d,%d,%s" % [chapter, sub, room]
	if room_over.has(k): return room_over[k]
	return room_defaults.get(room, -1)

func play_room(room: String, chapter := -1, sub := -1) -> void:
	play_song(song_for_room(room, chapter, sub))

func play_song(s: int) -> void:
	var w := s if (s >= 0 and s < 27) else -2
	if player == null or w == cur_song or (w == -2 and cur_song < 0): return
	mtx.lock()
	# AudioStreamGenerator can only be cleared while stopped: stop, clear, restart => old audio is gone instantly
	player.stop()
	gen = AudioStreamGenerator.new(); gen.mix_rate = EpfMusic.MIX_RATE; gen.buffer_length = 0.12
	player.stream = gen          # a fresh generator = an empty buffer
	player.play()
	pb = player.get_stream_playback()
	want_song = w
	mtx.unlock()

func _run() -> void:
	var chunk := 512
	var buf := PackedVector2Array()
	while running:
		mtx.lock()
		var w := want_song; want_song = -1
		if w != -1:
			if w == -2:
				cur_song = -2; eng.voices.clear(); eng.ch.clear()
			else:
				eng.voices.clear(); eng.start(w); cur_song = w; carry = 0.0
		var ok := pb != null and pb.get_frames_available() >= chunk and cur_song >= 0 and not eng.ch.is_empty()
		mtx.unlock()
		if not ok:
			OS.delay_msec(4); continue
		buf.resize(chunk); buf.fill(Vector2.ZERO)
		var done := 0
		while done < chunk:
			if carry <= 0.0:
				eng.tick(); eng.apply_events()
				carry += eng.tick_seconds()
			var n := mini(chunk - done, maxi(1, int(ceil(carry * EpfMusic.MIX_RATE))))
			eng.master = 0.0 if muted else volume
			eng.mix(n, buf, done, interp)
			done += n; carry -= float(n) / EpfMusic.MIX_RATE
		for i in chunk:
			var f := buf[i]
			buf[i] = Vector2(clampf(f.x, -1.0, 1.0), clampf(f.y, -1.0, 1.0))
		mtx.lock()
		if want_song == -1: pb.push_buffer(buf)   # a newer request arrived while mixing: drop this stale chunk
		mtx.unlock()

func _exit_tree() -> void:
	running = false
	if thread: thread.wait_to_finish()
	if pre_thread: pre_thread.wait_to_finish()
