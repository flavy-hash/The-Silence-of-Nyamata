extends Node
## Audio playback: ambience, music and voice-over.
##
## Real audio files are optional. Put them at:
##   res://audio/ambience/<key>.ogg   e.g. village_day.ogg, village_dusk.ogg
##   res://audio/music/<key>.ogg
##   voice clips: any path referenced by a dialogue node's "voice" key
## If a file is missing, ambience falls back to a quiet procedural placeholder
## (soft wind plus occasional birds) and music/voice are simply silent.
## Keep everything restrained; this game avoids sensational sound effects.

const AMBIENCE_DIR := "res://audio/ambience/"
const MUSIC_DIR := "res://audio/music/"

var _ambience: AudioStreamPlayer
var _music: AudioStreamPlayer
var _voice: AudioStreamPlayer

# Procedural placeholder ambience.
var _gen_player: AudioStreamPlayer
var _gen_playback: AudioStreamGeneratorPlayback
var _gen_rate := 22050.0
var _gen_mode := ""            # "", "day", "dusk"
var _noise := 0.0
var _noise2 := 0.0
var _bird_t := 0.0             # time until next bird call
var _bird_phase := 0.0
var _bird_len := 0.0
var _bird_pos := 0.0
var _bird_freq := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ambience = _make_player(-8.0)
	_music = _make_player(-14.0)
	_voice = _make_player(0.0)
	_gen_player = _make_player(-20.0)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _gen_rate
	gen.buffer_length = 0.25
	_gen_player.stream = gen


func _make_player(volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = volume_db
	add_child(p)
	return p


func play_ambience(key: String) -> void:
	var path := AMBIENCE_DIR + key + ".ogg"
	if ResourceLoader.exists(path):
		_stop_generator()
		_ambience.stream = load(path)
		_ambience.play()
	else:
		_ambience.stop()
		_start_generator("dusk" if key.ends_with("dusk") else "day")


func stop_ambience() -> void:
	_ambience.stop()
	_stop_generator()


func play_music(key: String) -> void:
	var path := MUSIC_DIR + key + ".ogg"
	if ResourceLoader.exists(path):
		_music.stream = load(path)
		_music.play()


func stop_music() -> void:
	_music.stop()


func play_voice(path: String) -> void:
	if path != "" and ResourceLoader.exists(path):
		_voice.stream = load(path)
		_voice.play()


func stop_voice() -> void:
	_voice.stop()


# --- Procedural placeholder ------------------------------------------------------

func _start_generator(mode: String) -> void:
	_gen_mode = mode
	if not _gen_player.playing:
		_gen_player.play()
		_gen_playback = _gen_player.get_stream_playback()


func _stop_generator() -> void:
	_gen_mode = ""
	_gen_player.stop()
	_gen_playback = null


func _process(_delta: float) -> void:
	if _gen_playback == null or _gen_mode == "":
		return
	var frames := _gen_playback.get_frames_available()
	var birds := _gen_mode == "day"
	for i in frames:
		# Wind: doubly low-passed white noise, gently modulated.
		_noise = lerp(_noise, _rng.randf_range(-1.0, 1.0), 0.02)
		_noise2 = lerp(_noise2, _noise, 0.05)
		var s := _noise2 * 1.6
		# Birds: short frequency-swept chirps at random intervals.
		if birds:
			_bird_t -= 1.0 / _gen_rate
			if _bird_t <= 0.0 and _bird_len <= 0.0:
				_bird_len = _rng.randf_range(0.06, 0.14)
				_bird_pos = 0.0
				_bird_freq = _rng.randf_range(2600.0, 4200.0)
				_bird_t = _rng.randf_range(0.15, 3.5)
			if _bird_len > 0.0:
				var k := _bird_pos / _bird_len
				var f := _bird_freq * (1.0 + 0.35 * sin(k * PI))
				_bird_phase += TAU * f / _gen_rate
				s += sin(_bird_phase) * sin(k * PI) * 0.05
				_bird_pos += 1.0 / _gen_rate
				if _bird_pos >= _bird_len:
					_bird_len = 0.0
		_gen_playback.push_frame(Vector2(s, s))
