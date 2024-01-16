extends Node

signal incoming_data(data)

const BUFFER_SIZE := 480

var active := false
var effect: AudioEffectCapture = null
var client: Client = null

var audio_thread = Thread.new()

var _player_pool := {}

func _ready():
	client = get_parent().get_node("Client")
	_update_player_pool()

	$Recorder.stream = AudioStreamMicrophone.new()
	$Recorder.play()

	var idx = AudioServer.get_bus_index("Record")
	effect = AudioServer.get_bus_effect(idx, 0)
	effect.buffer_length = 0.1
	effect.clear_buffer()

	audio_thread.start(audio_processing_loop)

func _process_audio() -> void:
	if has_data() and active:
		call_deferred("rpc", "play_data", get_data())

func _update_player_pool() -> void:
	for p in client.multiplayer.get_peers():
		if _player_pool.has(p):
			continue
		_player_pool[p] = _create_player()

func _create_player() -> AudioStreamPlayer:
	var p = AudioStreamPlayer.new()
	var g = AudioStreamGenerator.new()
	g.buffer_length = 0.1
	g.mix_rate = 48000
	p.stream = g
	add_child(p)
	p.play()
	return p

func _get_generator(id: int) -> AudioStreamGeneratorPlayback:
	return _player_pool[id].get_stream_playback()

func start_recording() -> void:
	active = true

func stop_recording() -> void:
	active = false

func has_data() -> bool:
	return effect.can_get_buffer(BUFFER_SIZE)

func get_data() -> PackedFloat32Array:
	var data = effect.get_buffer(BUFFER_SIZE)
	return Opus.encode(data)

func clear_data() -> void:
	effect.clear_buffer()

@rpc("any_peer", "call_remote", "unreliable_ordered")
func play_data(data: PackedFloat32Array) -> void:
	var id = client.multiplayer.get_remote_sender_id()
	_update_player_pool()

	var decoded = Opus.decode(data)
	for b in range(0, BUFFER_SIZE):
		_get_generator(id).push_frame(decoded[b])

func audio_processing_loop():
	var target_frame_time_ms = 1000 / 200.0 # 200 FPS
	while true:
		var start_time = Time.get_ticks_msec()

		_process_audio()

		var end_time = Time.get_ticks_msec()
		var elapsed_time = end_time - start_time
		var sleep_time = target_frame_time_ms - elapsed_time

		if sleep_time > 0:
			OS.delay_msec(sleep_time)
