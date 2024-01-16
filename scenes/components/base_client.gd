class_name BaseClient
extends Node

signal connected
signal disconnected
signal connection_timeout
signal lobby_joined(lobby)
signal lobby_sealed
signal lobby_already_exists
signal peer_connected(id)
signal peer_disconnected(id)
signal offer_received(id, offer)
signal answer_received(id, answer)
signal candidate_received(id, mid, index, sdp)

enum Message {
	JOIN,
	ID,
	PEER_CONNECT,
	PEER_DISCONNECT,
	OFFER,
	ANSWER,
	CANDIDATE,
	SEAL,
	CREATE_LOBBY,
	LOBBY_ALREADY_EXISTS,
}

@export var server_address := "ws://localhost:9080"
@export var host := false

var ws: WebSocketPeer = WebSocketPeer.new()
var rtc_mp: WebRTCMultiplayerPeer = WebRTCMultiplayerPeer.new()

var _lobby := ""
var _last_state := WebSocketPeer.STATE_CLOSED


func _process(_delta: float) -> void:
	ws.poll()
	var state = ws.get_ready_state()

	if state != _last_state and state == WebSocketPeer.STATE_OPEN:
		if host:
			create_lobby()
		else:
			join_lobby()

	while state == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count():
		var r = _handle_response(ws.get_packet().get_string_from_utf8())
		if not r:
			print("Error while parsing message: ", r)

	_last_state = state


func start(lobby: String, h: bool) -> void:
	await close()
	_lobby = lobby
	host = h
	ws.connect_to_url(server_address)

	# Timeout
	await get_tree().create_timer(3.0).timeout
	if ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		connection_timeout.emit()
		close()


func stop() -> void:
	multiplayer.multiplayer_peer = null
	rtc_mp.close()
	close()


func close() -> bool:
	ws.close()
	while ws.get_ready_state() != ws.STATE_CLOSED:
		await get_tree().create_timer(0.1).timeout
	if ws.get_close_code() == -1:
		return false

	_lobby = ""

	print("Closed connection")
	disconnected.emit()
	return true


func create_lobby() -> void:
	if _send_msg(Message.CREATE_LOBBY, 0, _lobby) != 0:
		print("Error while creating lobby: ", _lobby)


func join_lobby() -> void:
	if _send_msg(0, 0, _lobby) != 0:
		print("Error while joining lobby: ", _lobby)


func _handle_response(r: String) -> bool:
	var parsed = JSON.parse_string(r)

	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	if not parsed.has("type"):
		return false
	if not parsed.has("id"):
		return false
	if not parsed.has("data"):
		return false

	var msg = parsed as Dictionary
	var type = str(msg.type).to_int()
	var id = str(msg.id).to_int()

	match type:
		Message.ID:
			connected.emit(id)
		Message.JOIN:
			lobby_joined.emit(msg.data)
		Message.SEAL:
			lobby_sealed.emit()
		Message.PEER_CONNECT:
			peer_connected.emit(id)
		Message.PEER_DISCONNECT:
			peer_disconnected.emit(id)
		Message.OFFER:
			offer_received.emit(id, msg.data)
		Message.ANSWER:
			answer_received.emit(id, msg.data)
		Message.LOBBY_ALREADY_EXISTS:
			lobby_already_exists.emit()
		Message.CANDIDATE:
			var candidate: PackedStringArray = msg.data.split("\n", false)
			if candidate.size() != 3:
				return false
			if not candidate[1].is_valid_int():
				return false
			candidate_received.emit(id, candidate[0], candidate[1].to_int(), candidate[2])
		_:
			return false

	return true


func seal_lobby():
	return _send_msg(Message.SEAL, 0)


func send_candidate(id, mid, index, sdp) -> int:
	return _send_msg(Message.CANDIDATE, id, "\n%s\n%d\n%s" % [mid, index, sdp])


func send_offer(id, offer) -> int:
	return _send_msg(Message.OFFER, id, offer)


func send_answer(id, answer) -> int:
	return _send_msg(Message.ANSWER, id, answer)


func _send_msg(type: int, id: int, data:="") -> int:
	return ws.send_text(JSON.stringify({
		"type": type,
		"id": id,
		"data": data
	}))
