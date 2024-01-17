extends Node

const BUFFER_SIZE := 480

var active := false
var effect: AudioEffectCapture = null
var client: Client = null

var audio_thread = Thread.new()

var _player_pool := {}
var _encoder := Opus.new()

func _ready():
	client = get_parent().get_node("Client")
	_update_player_pool()

	$Recorder.stream = AudioStreamMicrophone.new()
	$Recorder.play()

	var idx = AudioServer.get_bus_index("Record")
	effect = AudioServer.get_bus_effect(idx, 0)
	effect.buffer_length = 0.1
	effect.clear_buffer()

	audio_thread.start(_audio_process, Thread.PRIORITY_HIGH)


func _audio_process():
	while true:
		if has_data() and active:
			var data = get_data()
			call_deferred("rpc", "play_data", data)
		else:
			OS.delay_msec(10)


func _update_player_pool() -> void:
	for p in client.multiplayer.get_peers():
		if _player_pool.has(p):
			continue
		_player_pool[p] = _create_player()


func _create_player() -> Array:
	var p = AudioStreamPlayer.new()
	var g = AudioStreamGenerator.new()
	g.buffer_length = 0.1
	g.mix_rate = 48000
	p.stream = g
	add_child(p)
	p.play()
	var decoder = Opus.new()
	add_child(decoder)
	return [p, decoder]


func _get_generator(id: int) -> AudioStreamGeneratorPlayback:
	return _player_pool[id][0].get_stream_playback()


func _get_opus_instance(id: int) -> Opus:
	return _player_pool[id][1]


func start_recording() -> void:
	active = true


func stop_recording() -> void:
	active = false


func has_data() -> bool:
	return effect.can_get_buffer(BUFFER_SIZE)


func get_data() -> PackedFloat32Array:
	var data = effect.get_buffer(BUFFER_SIZE)
	return _encoder.encode(data)


func clear_data() -> void:
	effect.clear_buffer()


@rpc("any_peer", "call_remote", "reliable")
func play_data(data: PackedFloat32Array) -> void:
	var id = client.multiplayer.get_remote_sender_id()
	_update_player_pool()
	_get_opus_instance(id).decode_and_play(_get_generator(id), data)

