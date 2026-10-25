class_name BlsquiWebRTCPresence
extends Node

signal message_received(data: Dictionary)
signal state_changed(state: Dictionary)

const SIGNALING_API: String = "https://api.blsqui-signer.net/api/rtc/session"

var _state: Dictionary = {
	"connected": false,
	"gameOnline": false,
	"canUseItem": false,
	"lastPingMs": 0
}

var pc: WebRTCPeerConnection = null
var dc: WebRTCDataChannel = null
var active_address: String = ""
var is_connecting: bool = false

var _pending_offer_sdp: String = ""
var _pending_offer_type: String = ""

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	if pc:
		pc.poll()

	if dc:
		dc.poll()
		var channel_state: int = dc.get_ready_state()

		if channel_state == WebRTCDataChannel.STATE_OPEN and not _state["connected"]:
			print("✅ [Godot WebRTC DataChannel OPEN]")
			_update_state({"connected": true})
		elif channel_state == WebRTCDataChannel.STATE_CLOSED and _state["connected"]:
			print("🛑 [Godot WebRTC DataChannel CLOSED]")
			_update_state({
				"connected": false,
				"gameOnline": false,
				"canUseItem": false
			})

		# Read incoming packets from the Pion Hub DataChannel
		while dc.get_available_packet_count() > 0:
			var packet: PackedByteArray = dc.get_packet()
			var raw_text: String = packet.get_string_from_utf8()
			var json: JSON = JSON.new()
			if json.parse(raw_text) == OK and json.get_data() is Dictionary:
				var msg: Dictionary = json.get_data()
				print("📩 [Godot WebRTC RECV]: ", msg)
				_handle_incoming_message(msg)

func get_state() -> Dictionary:
	return _state.duplicate()

func _update_state(partial: Dictionary) -> void:
	for key in partial.keys():
		_state[key] = partial[key]
	state_changed.emit(_state.duplicate())

## Starts the WebRTC handshake with Pion Hub via HTTP SDP exchange
func init_presence(player_address: String, role: String = "game") -> void:
	var clean_addr: String = player_address.to_lower().strip_edges()
	if clean_addr == "":
		push_warning("[WebRTC] Missing player address. Aborting handshake.")
		return

	if is_connecting or (pc != null and active_address == clean_addr and _state["connected"]):
		return

	is_connecting = true
	active_address = clean_addr
	cleanup()

	pc = WebRTCPeerConnection.new()
	
	# Connect Godot's WebRTC signaling callbacks
	pc.session_description_created.connect(_on_session_description_created.bind(role, clean_addr))
	pc.ice_candidate_created.connect(_on_ice_candidate_created)

	var ice_config: Dictionary = {
		"iceServers": [
			{ "urls": ["stun:stun.l.google.com:19302"] },
			{ "urls": ["stun:stun.cloudflare.com:3478"] }
		]
	}
	pc.initialize(ice_config)

	dc = pc.create_data_channel("blsqui-presence", { "negotiated": false })

	# Create local SDP offer (will trigger session_description_created signal)
	var err: Error = pc.create_offer()
	if err != OK:
		push_error("[WebRTC] Failed to create offer: %d" % err)
		is_connecting = false


func _on_session_description_created(type: String, sdp: String, role: String, clean_addr: String) -> void:
	if not pc:
		return

	# 1. Set local description on our peer connection
	pc.set_local_description(type, sdp)

	# 2. Wait a brief moment for ICE candidates to append to the SDP (or gather complete)
	await get_tree().create_timer(0.3).timeout

	# 3. Post full offer to Pion Hub
	var payload: Dictionary = {
		"role": role,
		"player": clean_addr,
		"sdp": {
			"type": type,
			"sdp": sdp
		}
	}

	var http_req: HTTPRequest = HTTPRequest.new()
	add_child(http_req)

	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json"
	])

	print("[WebRTC] Posting offer to Pion Hub for room: ", clean_addr)
	var err: Error = http_req.request(SIGNALING_API, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		http_req.queue_free()
		is_connecting = false
		return

	var res: Array = await http_req.request_completed
	http_req.queue_free()

	var code: int = res[1]
	var body_text: String = (res[3] as PackedByteArray).get_string_from_utf8()

	if code < 200 or code >= 300:
		push_error("[WebRTC] Handshake failed [HTTP %d]: %s" % [code, body_text])
		_update_state({"connected": false})
		is_connecting = false
		return

	var json: JSON = JSON.new()
	if json.parse(body_text) == OK and json.get_data() is Dictionary:
		var answer: Dictionary = json.get_data()
		var answer_sdp: String = ""
		
		# Hub may return either {"sdp": "..."} or {"sdp": {"sdp": "...", "type": "answer"}}
		if answer.has("sdp"):
			if answer["sdp"] is Dictionary:
				answer_sdp = str(answer["sdp"].get("sdp", ""))
			else:
				answer_sdp = str(answer["sdp"])

		if answer_sdp != "":
			print("[WebRTC] Remote description (answer) set successfully.")
			pc.set_remote_description("answer", answer_sdp)
		else:
			push_error("[WebRTC] Answer missing SDP body: %s" % body_text)

	is_connecting = false


func _on_ice_candidate_created(media: String, index: int, name: String) -> void:
	# Godot 4 WebRTC gathers candidates directly into the session description when polled
	pass


func send_data(data: Variant) -> void:
	if dc:
		var state: int = dc.get_ready_state()
		if state == WebRTCDataChannel.STATE_OPEN:
			var payload: String = data if data is String else JSON.stringify(data)
			print("📤 [Godot WebRTC SEND]: ", payload)
			var err = dc.put_packet(payload.to_utf8_buffer())
			if err != OK:
				push_error("[WebRTC] put_packet error code: %d" % err)
		else:
			push_warning("[WebRTC] Send dropped: DataChannel ready state is %d (expected 1/OPEN)" % state)
	else:
		push_warning("[WebRTC] Send failed: dc is null")

func _handle_incoming_message(msg: Dictionary) -> void:
	var msg_type: String = msg.get("type", "")

	if msg_type == "PRESENCE_UPDATE":
		_update_state({
			"gameOnline": msg.get("status") == "GAME_CONNECTED",
			"canUseItem": bool(msg.get("can_use_item", false))
		})

	if msg_type == "ITEM_USE_REQUESTED":
		var item_id: String = msg.get("itemId", "")
		var serial_number: int = int(msg.get("serialNumber", 0))
		var flix_id: String = msg.get("flixId", "")
		var is_testnet: bool = msg.get("isTestnet", true)

		var tx_res: Dictionary = await BlsquiSDK.request_transaction({
			"is_testnet": is_testnet,
			"flix_id": flix_id,
			"args": {
				"itemId": item_id,
				"serialNumber": serial_number
			}
		})

		if tx_res.get("status") == "SEALED":
			send_data({
				"type": "ITEM_USED",
				"itemId": item_id,
				"serialNumber": serial_number,
				"txId": tx_res.get("txId", ""),
				"timestamp": int(Time.get_unix_time_from_system() * 1000)
			})
			
			message_received.emit({
				"type": "ITEM_USE_COMPLETED",
				"itemId": item_id,
				"serialNumber": serial_number,
				"txId": tx_res.get("txId", "")
			})

	message_received.emit(msg)


func cleanup() -> void:
	if dc:
		dc.close()
		dc = null
	if pc:
		pc.close()
		pc = null
	active_address = ""
	is_connecting = false
	_update_state({
		"connected": false,
		"gameOnline": false,
		"canUseItem": false
	})
