class_name BlsquiCurrentUser
extends Node

signal user_updated(user_state: Dictionary)
signal slots_updated(slots: Array)
signal item_use_requested(payload: Dictionary)

const TESTNET_BASE_URL: String = "https://lab.blsqui.net"
const MAINNET_BASE_URL: String = "https://wallet.blsqui.net"

var app_id: String = ""
var publisher_address: String = ""
var network: String = "testnet"

var user_state: Dictionary = {
	"addr": "",
	"loggedIn": false,
	"avatarImage": "",
	"userName": "",
	"network": "testnet",
	"slot": [],
	"lastUsedItem": null
}

var presence: BlsquiWebRTCPresence = null
var session_channel_key: String = ""
var heartbeat_timer: Timer = null

func _init() -> void:
	presence = BlsquiWebRTCPresence.new()
	add_child(presence)
	presence.message_received.connect(_on_presence_message)

	heartbeat_timer = Timer.new()
	heartbeat_timer.wait_time = 10.0
	heartbeat_timer.one_shot = false
	heartbeat_timer.timeout.connect(_send_presence_live_signal)
	add_child(heartbeat_timer)

func configure(cfg_app_id: String, cfg_pub_addr: String, cfg_network: String = "testnet") -> void:
	app_id = cfg_app_id.to_lower().strip_edges()
	publisher_address = cfg_pub_addr.strip_edges()
	network = cfg_network
	user_state["network"] = network

func generate_channel_key() -> String:
	var crypto: Crypto = Crypto.new()
	return crypto.generate_random_bytes(32).hex_encode()

func get_or_create_channel_key() -> String:
	if session_channel_key == "":
		session_channel_key = generate_channel_key()
	return session_channel_key

## Opens system browser pointing to the Web Wallet Dashboard and connects/syncs game presence
func open_dashboard() -> void:
	var base_url: String = TESTNET_BASE_URL if network == "testnet" else MAINNET_BASE_URL
	var channel_key: String = get_or_create_channel_key()

	# Verify active DataChannel or initiate WebRTC presence using channel_key as the room ID
	presence.verify_or_reconnect(channel_key)

	# Build URL parameters
	var params: Array = [
		"channel_key=%s" % channel_key.uri_encode()
	]
	if app_id != "":
		params.append("app_id=%s" % app_id.uri_encode())
	if publisher_address != "":
		params.append("publisher_address=%s" % publisher_address.uri_encode())
	if user_state["addr"] != "":
		params.append("addr=%s" % str(user_state["addr"]).uri_encode())

	var full_url: String = "%s/?%s" % [base_url, "&".join(params)]
	print("[BlsquiSDK] Opening Dashboard: ", full_url)
	OS.shell_open(full_url)

func set_state(updates: Dictionary) -> void:
	var prev_logged_in: bool = user_state["loggedIn"]

	for key in updates.keys():
		user_state[key] = updates[key]

	if updates.has("addr"):
		user_state["loggedIn"] = (str(updates["addr"]).strip_edges() != "")

	if not prev_logged_in and user_state["loggedIn"]:
		heartbeat_timer.start()
		_send_presence_live_signal()
	elif prev_logged_in and not user_state["loggedIn"]:
		heartbeat_timer.stop()

	user_updated.emit(user_state.duplicate())

	if updates.has("slot") and updates["slot"] is Array:
		slots_updated.emit(updates["slot"].duplicate())

func _send_presence_live_signal() -> void:
	presence.send_data({
		"type": "PRESENCE_PONG",
		"role": "game",
		"player": str(user_state["addr"]).to_lower(),
		"status": "LIVE",
		"game_online": true,
		"timestamp": int(Time.get_unix_time_from_system() * 1000)
	})

func _on_presence_message(msg: Dictionary) -> void:
	var msg_type: String = msg.get("type", "")

	if msg_type == "PRESENCE_PING":
		# Adopt player address from dashboard ping if local address is empty
		if str(user_state["addr"]).strip_edges() == "":
			var ping_player: String = str(msg.get("player", "")).strip_edges()
			if ping_player != "":
				user_state["addr"] = ping_player
		_send_presence_live_signal()
		return

	if msg_type in ["BLSQUI_USER_UPDATE", "SLOT_SYNC", "BLSQUI_SLOT_SYNC"]:
		var new_addr: String = msg.get("address", msg.get("player", user_state["addr"]))
		set_state({
			"addr": new_addr,
			"userName": msg.get("userName", msg.get("user_name", user_state["userName"])),
			"avatarImage": msg.get("avatarImage", msg.get("avatar_image", user_state["avatarImage"])),
			"slot": msg.get("slot", msg.get("slots", [])),
			"loggedIn": (new_addr != "")
		})
		return

	if msg_type in ["STAGE_REORDERED", "ITEM_EQUIPPED"]:
		if msg.has("slots") and msg["slots"] is Array:
			set_state({ "slot": msg["slots"] })
		return

	if msg_type == "BLSQUI_LOGOUT":
		set_state({
			"addr": "",
			"loggedIn": false,
			"slot": [],
			"avatarImage": "",
			"userName": ""
		})
		return

	if msg_type == "ITEM_USE_REQUESTED":
		var req_publisher: String = str(msg.get("publisherAddress", msg.get("publisher_address", ""))).strip_edges()
		if req_publisher == "":
			req_publisher = publisher_address

		var req_app_id: String = str(msg.get("appId", msg.get("app_id", ""))).strip_edges()
		if req_app_id == "":
			req_app_id = app_id

		var payload: Dictionary = {
			"type": "ITEM_USE_REQUESTED",
			"player": str(msg.get("player", user_state["addr"])),
			"publisherAddress": req_publisher,
			"appId": req_app_id,
			"app_id": req_app_id,
			"itemId": str(msg.get("itemId", msg.get("item_id", ""))),
			"serialNumber": int(msg.get("serialNumber", msg.get("serial_number", 0))),
			"flixId": str(msg.get("flixId", msg.get("flix_id", ""))),
			"isTestnet": bool(msg.get("isTestnet", network == "testnet"))
		}
		print("[BlsquiSDK] Dispatching item_use_requested -> Publisher: %s, App: %s, Item: %s, Serial: %d, FLIX: %s" % [
			payload["publisherAddress"],
			payload["appId"],
			payload["itemId"],
			payload["serialNumber"],
			payload["flixId"]
		])
		item_use_requested.emit(payload)
		return

	if msg_type == "ITEM_USE_COMPLETED":
		set_state({
			"lastUsedItem": {
				"itemId": msg.get("itemId", ""),
				"serialNumber": msg.get("serialNumber", 0),
				"txId": msg.get("txId", "")
			}
		})

## Sends an item action trigger to the active WebRTC dashboard session
func trigger_item_action(item_id: String) -> void:
	if item_id == "":
		push_warning("[BlsquiSDK] trigger_item_action called with empty itemId")
		return

	if not presence or not presence.get_state().get("connected", false):
		push_warning("[BlsquiSDK] WebRTC connection not active. Cannot trigger item action.")
		return

	var packet: Dictionary = {
		"type": "TRIGGER_ITEM_ACTION",
		"itemId": item_id,
		"player": str(user_state["addr"]).to_lower(),
		"timestamp": int(Time.get_unix_time_from_system() * 1000)
	}

	print("[BlsquiSDK] Triggering item action for: ", item_id)
	presence.send_data(packet)
