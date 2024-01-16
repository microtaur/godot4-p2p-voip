extends Control

const names = [
	"John", "Paul", "Gaylord", "Adalbert", "Oli",
	"Elena", "Marta", "Leo", "Nina", "Samuel",
	"Aisha", "Ravi", "Chloe", "Hector", "Yasmin",
	"Boris", "Luna", "Anastasia", "Kenji", "Freya"
]

var _peers_in_list := {}
var _is_connected := false

func _ready():
	randomize()

	%Host.pressed.connect(_host)
	%Join.pressed.connect(_join)
	%Quit.pressed.connect(_quit)
	%Start.pressed.connect(_seal)

	$Client.lobby_joined.connect(_connected)
	$Client.connection_timeout.connect(_timeout)
	$Client.multiplayer.peer_connected.connect(_peer_connected)
	$Client.multiplayer.peer_disconnected.connect(_peer_disconnected)
	$Client.lobby_sealed.connect(_sealed)
	$Client.lobby_already_exists.connect(_lobby_exists)

	%Nickname.text = names.pick_random()
	%ChatInput.text_submitted.connect(_send_text)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("push_to_talk"):
		%Lobby/VBoxContainer/SpeakIndicator.text = "SPEAKING"
		$Voice.start_recording()
	if event.is_action_released("push_to_talk"):
		%Lobby/VBoxContainer/SpeakIndicator.text = "Press SPACE to speak"
		$Voice.stop_recording()


func _host() -> void:
	$Client.start(%HostLobby.text, true)
	%Host.text = " Creating... "
	%Host.disabled = true
	%HostLobby.editable = false


func _join() -> void:
	$Client.start(%JoinLobby.text, false)


func _connected(lobby: String) -> void:
	%ConnectionPanel.hide()
	%LobbyName.text = lobby
	%Lobby.show()

	%Start.visible = $Client.host
	%PlayerList.add_item(%Nickname.text)

	_is_connected = true


func _peer_connected(id) -> void:
	if id == multiplayer.get_unique_id():
		return
	rpc_id(id, "request_name")


func _peer_disconnected(id) -> void:
	if not _peers_in_list.has(id):
		return

	var i = %PlayerList.get_item_count() - 1
	while i > 0:
		if %PlayerList.get_item_text(i) == _peers_in_list[id]:
			%PlayerList.remove_item(i)
			break
		else:
			i -= 1

	_peers_in_list.erase(id)


func _timeout() -> void:
	%Host.text = " Host "
	%Host.disabled = false
	%HostLobby.editable = true


func _quit() -> void:
	_peers_in_list.clear()

	$Client.stop()
	%Lobby.hide()
	%ConnectionPanel.show()
	%PlayerList.clear()
	%ChatBox.clear()
	_timeout()


func _seal() -> void:
	$Client.seal_lobby()


func _sealed() -> void:
	%ChatBox.append_text("[color=#dd0000]The lobby has been sealed.[/color]\n")

func _lobby_exists() -> void:
	%ErrorBox.popup()
	_quit()


func _send_text(text: String) -> void:
	send_text.rpc("[b]%s[/b]: %s\n" % [%Nickname.text, text])
	%ChatInput.clear()


@rpc("any_peer", "call_local")
func send_text(text):
	%ChatBox.append_text(text)


@rpc("any_peer", "call_remote", "reliable")
func request_name() -> void:
	rpc_id(multiplayer.get_remote_sender_id(), "set_nickname", %Nickname.text)


@rpc("any_peer", "call_local", "reliable")
func set_nickname(nickname: String) -> void:
	var peer = multiplayer.get_remote_sender_id()
	if peer in _peers_in_list:
		return

	_peers_in_list[peer] = nickname
	%PlayerList.add_item(nickname)
