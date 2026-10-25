class_name BlsquiSDK
extends Node

# --- Gateway, Session Sign & Polling Endpoints ---
const MAINNET_GATEWAY_URL: String = "https://wallet.blsqui.net/transaction"
const TESTNET_GATEWAY_URL: String = "https://lab.blsqui.net/transaction"
const MAINNET_SESSION_SIGN_API: String = "https://wallet.blsqui.net/api/session/sign"
const TESTNET_SESSION_SIGN_API: String = "https://lab.blsqui.net/api/session/sign"
const MAINNET_POLL_API: String = "https://wallet.blsqui.net/api/status"
const TESTNET_POLL_API: String = "https://lab.blsqui.net/api/status"

# Default FLIX Template (10 FLOW entry fee)
const DEFAULT_FLIX_ID: String = "7d9d4b154547d7f6ec95e8b95741ed84663592d8c0016dbc4b28b6f9bf435ba5"
const POLL_INTERVAL_SEC: float = 1.5
const TIMEOUT_SECONDS: float = 300.0

# SDK Internal State
static var _is_canceled: bool = false


## Primary Entry Point: Requests a signed session token, opens the system browser,
## and polls the backend for on-chain completion.
##
## @param options Dictionary containing:
##   - "is_testnet": bool (default: true)
##   - "flix_id": String (default: DEFAULT_FLIX_ID)
##   - "args": Dictionary (e.g. {"to": "0x1234...", "amount": "10.0"})
##   - "verbose": bool (default: false)
##
## @returns Dictionary matching TransactionResult:
##   - "status": "SEALED" | "FAILED" | "EXPIRED" | "TIMEOUT" | "CANCELED"
##   - "txId": String
##   - "nonce": String
##   - "payer": String
##   - "to": String
##   - "amount": String
##   - "token": String
##   - "txFee": Variant (String or null)
##   - "error": String
##   - "errorMessage": Variant (String or null)
static func request_transaction(options: Dictionary = {}) -> Dictionary:
	_is_canceled = false

	var is_testnet: bool = options.get("is_testnet", true)
	var flix_id: String = str(options.get("flix_id", DEFAULT_FLIX_ID))
	var args: Dictionary = options.get("args", {})
	var verbose: bool = options.get("verbose", false)

	var base_url: String = TESTNET_GATEWAY_URL if is_testnet else MAINNET_GATEWAY_URL
	var current_nonce: String = generate_client_nonce()
	var current_time: int = int(Time.get_unix_time_from_system())

	# Prepare payload for session signing
	var sign_payload: Dictionary = {
		"flix": flix_id,
		"issued_time": current_time,
		"nonce": current_nonce
	}

	# Merge custom transaction arguments into payload
	for key: Variant in args.keys():
		var val_str: String = str(args[key]).strip_edges()
		if val_str != "":
			sign_payload[str(key)] = args[key]

	# Acquire asymmetrically signed JWT session token from edge functions
	var token_res: Dictionary = await _acquire_signed_session_token(is_testnet, sign_payload, verbose)
	if not token_res.get("success", false):
		return {
			"status": "FAILED",
			"nonce": current_nonce,
			"error": "Failed to sign transaction session: %s" % token_res.get("error", "Unknown error")
		}

	var signed_token: String = token_res.get("token", "")

	# Build tamper-proof request URL using the single signed token
	var full_url: String = "%s?request=%s" % [base_url, signed_token.uri_encode()]

	if verbose:
		print("[BlsquiSDK] Mode: Godot Native Browser [%s]" % ["TESTNET" if is_testnet else "MAINNET"])
		print("[BlsquiSDK] Wallet Gateway URL: %s" % full_url)
		print("[BlsquiSDK] Nonce: %s" % current_nonce)

	# Launch system browser
	var launch_err: Error = OS.shell_open(full_url)
	if launch_err != OK:
		push_error("[BlsquiSDK] Failed to launch system browser.")
		return {
			"status": "FAILED",
			"nonce": current_nonce,
			"error": "Failed to launch system browser"
		}

	# Poll backend server for transaction status
	return await _poll_transaction_status(is_testnet, current_nonce, verbose)


## Cancels any ongoing transaction polling loop
static func cancel_transaction() -> void:
	_is_canceled = true


## Requests an asymmetrically signed JWT session token via /api/session/sign
static func _acquire_signed_session_token(is_testnet: bool, payload: Dictionary, verbose: bool) -> Dictionary:
	var main_tree: SceneTree = Engine.get_main_loop() as SceneTree
	var http_req: HTTPRequest = HTTPRequest.new()
	main_tree.root.add_child(http_req)

	var sign_api_url: String = TESTNET_SESSION_SIGN_API if is_testnet else MAINNET_SESSION_SIGN_API
	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json"
	])
	var json_body: String = JSON.stringify(payload)

	var err: Error = http_req.request(sign_api_url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		http_req.queue_free()
		return {"success": false, "error": "HTTPRequest setup failed: %d" % err}

	var response: Array = await http_req.request_completed
	http_req.queue_free()

	var response_code: int = response[1]
	var body: PackedByteArray = response[3]
	var body_text: String = body.get_string_from_utf8()

	var json: JSON = JSON.new()
	var parse_err: Error = json.parse(body_text)
	var data: Dictionary = json.get_data() if parse_err == OK and json.get_data() is Dictionary else {}

	if response_code < 200 or response_code >= 300:
		var error_msg: String = str(data.get("error", "HTTP_%d" % response_code))
		if verbose:
			push_error("[BlsquiSDK] Session token signing failed: %s" % error_msg)
		return {"success": false, "error": error_msg}

	var token: String = str(data.get("token", ""))
	if token == "":
		return {"success": false, "error": "Response missing signed token"}

	return {"success": true, "token": token}


## Async HTTP Polling Loop
static func _poll_transaction_status(is_testnet: bool, nonce: String, verbose: bool) -> Dictionary:
	var main_tree: SceneTree = Engine.get_main_loop() as SceneTree
	var http_req: HTTPRequest = HTTPRequest.new()
	main_tree.root.add_child(http_req)

	var poll_base: String = TESTNET_POLL_API if is_testnet else MAINNET_POLL_API
	var poll_url: String = "%s?nonce=%s" % [poll_base, nonce.uri_encode()]
	var start_time: float = Time.get_ticks_msec() / 1000.0

	while (Time.get_ticks_msec() / 1000.0 - start_time) < TIMEOUT_SECONDS:
		if _is_canceled:
			http_req.queue_free()
			if verbose:
				print("[BlsquiSDK] Transaction polling canceled by caller.")
			return {
				"status": "CANCELED",
				"nonce": nonce,
				"error": "Transaction canceled by user."
			}

		var err: Error = http_req.request(poll_url, ["Accept: application/json"])
		if err == OK:
			var response: Array = await http_req.request_completed
			var response_code: int = response[1]
			var body: PackedByteArray = response[3]

			if response_code == 200:
				var json: JSON = JSON.new()
				if json.parse(body.get_string_from_utf8()) == OK:
					var data: Dictionary = json.get_data()
					var status: String = str(data.get("status", "PENDING")).to_upper()

					if verbose:
						print("[BlsquiSDK Poll] HTTP 200 | Status: '%s' | Data: %s" % [status, data])

					if status == "SEALED":
						http_req.queue_free()
						var error_msg: Variant = data.get("errorMessage", null)

						# On-chain execution failure
						if error_msg != null and str(error_msg).strip_edges() != "":
							return {
								"status": "FAILED",
								"txId": data.get("txId", ""),
								"nonce": nonce,
								"payer": data.get("payer", ""),
								"error": "On-chain execution failed",
								"errorMessage": str(error_msg)
							}

						# On-chain success
						if verbose:
							print("[BlsquiSDK] 🎉 Transaction Sealed! TX ID: %s" % data.get("txId", ""))

						var tx_fee_val: Variant = data.get("txFee", data.get("tx_fee", null))

						return {
							"status": "SEALED",
							"txId": data.get("txId", ""),
							"nonce": nonce,
							"errorMessage": null,
							"payer": data.get("payer", ""),
							"to": data.get("to", ""),
							"amount": str(data.get("amount", "0.0")),
							"token": data.get("token", ""),
							"txFee": tx_fee_val
						}

					elif status == "EXPIRED":
						http_req.queue_free()
						if verbose:
							push_warning("[BlsquiSDK] Transaction EXPIRED on-chain.")
						return {
							"status": "EXPIRED",
							"nonce": nonce,
							"error": "Transaction expired on-chain"
						}
			elif verbose:
				push_warning("[BlsquiSDK Poll] Non-200 HTTP response: %d" % response_code)

		# Wait before next polling attempt
		await main_tree.create_timer(POLL_INTERVAL_SEC).timeout

	http_req.queue_free()
	if verbose:
		push_error("[BlsquiSDK] Transaction poll timed out after %s seconds." % TIMEOUT_SECONDS)

	return {
		"status": "TIMEOUT",
		"nonce": nonce,
		"error": "Transaction poll timed out after %s seconds." % TIMEOUT_SECONDS
	}


## Generates a 256-bit cryptographically secure hex nonce (lowercase 64-char SHA-256)
static func generate_client_nonce() -> String:
	var crypto: Crypto = Crypto.new()
	var random_bytes: PackedByteArray = crypto.generate_random_bytes(32)
	return random_bytes.hex_encode().sha256_text()

## Queries a user's equipped stage slots directly from Flow Access Nodes.
static func get_stage_slots(options: Dictionary) -> Array:
	return await BlsquiStageSlot.get_stage_slots(options)

static var current_user: BlsquiCurrentUser = null

static func open_dashboard(app_id: String = "", publisher_address: String = "", network: String = "testnet") -> void:
	if not current_user:
		var main_tree: SceneTree = Engine.get_main_loop() as SceneTree
		current_user = BlsquiCurrentUser.new()
		main_tree.root.add_child(current_user)
		current_user.configure(app_id, publisher_address, network)
	
	current_user.open_dashboard()

static func summon_dashboard(app_id: String = "", publisher_address: String = "", network: String = "testnet", on_update: Callable = Callable()) -> void:
	open_dashboard(app_id, publisher_address, network)
	if on_update.is_valid() and not current_user.user_updated.is_connected(on_update):
		current_user.user_updated.connect(on_update)

static func trigger_item_action(item_id: String) -> void:
	if current_user:
		current_user.trigger_item_action(item_id)
	else:
		push_warning("[BlsquiSDK] current_user is null. Call summon_dashboard first.")
