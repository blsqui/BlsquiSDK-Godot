class_name BlsquiSDK
extends Node

const MAINNET_URL: String = "https://signer.blsqui.net"
const TESTNET_URL: String = "https://testnet-signer.blsqui.net"
const POLL_INTERVAL: float = 1.5 # Check status every 1.5 seconds
const TIMEOUT_SECONDS: float = 300.0 # 5-minute timeout

## Primary Entry Point: Opens browser and polls backend server for completion.
## Pass `is_testnet = true` for Flow Testnet, or `false` for Mainnet.
static func request_transaction(
	amount: float, 
	destination: String, 
	is_testnet: bool = true, 
	verbose: bool = false
) -> Dictionary:
	var base_url: String = TESTNET_URL if is_testnet else MAINNET_URL
	var current_nonce: String = generate_client_nonce()
	var current_time: int = int(Time.get_unix_time_from_system())
	
	# 1. Build payment signer URL
	var full_url: String = "%s?nonce=%s&to=%s&price=%s&issued_time=%d" % [
		base_url,
		current_nonce,
		destination,
		str(amount),
		current_time
	]

	if verbose:
		print("[BlsquiSDK] Launching system browser (%s) -> %s" % ["TESTNET" if is_testnet else "MAINNET", full_url])
		print("[BlsquiSDK] Nonce: %s" % current_nonce)

	# 2. Open user browser
	var launch_err: Error = OS.shell_open(full_url)
	if launch_err != OK:
		push_error("[BlsquiSDK] Failed to open system browser.")
		return {"status": "FAILED", "error": "Failed to open system browser"}

	# 3. Poll backend server for transaction status
	if verbose:
		print("[BlsquiSDK] Polling backend for nonce: %s..." % current_nonce)
		
	var result: Dictionary = await _poll_transaction_status(base_url, current_nonce, verbose)
	return result


## Async HTTP polling loop
static func _poll_transaction_status(base_url: String, nonce: String, verbose: bool) -> Dictionary:
	var main_tree: SceneTree = Engine.get_main_loop() as SceneTree
	var http_req: HTTPRequest = HTTPRequest.new()
	main_tree.root.add_child(http_req)

	var poll_url: String = "%s/api/status?nonce=%s" % [base_url, nonce]
	var start_time: float = Time.get_ticks_msec() / 1000.0

	while (Time.get_ticks_msec() / 1000.0 - start_time) < TIMEOUT_SECONDS:
		var err: Error = http_req.request(poll_url)
		
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

					# If status is finalized on-chain, free node and return result
					if status in ["SEALED", "EXECUTED", "FINALIZED", "SUCCESS"]:
						http_req.queue_free()
						if verbose:
							print("[BlsquiSDK] 🎉 Transaction Sealed! TX ID: %s" % data.get("txId", ""))
							
						return {
							"status": status,
							"txId": data.get("txId", ""),
							"nonce": nonce,
							"errorMessage": data.get("errorMessage", null),
							"payer": data.get("payer", ""),
							"to": data.get("to", ""),
							"amount": data.get("amount", "0.0"),
							"token": data.get("token", "FLOW")
						}
					elif status == "EXPIRED":
						http_req.queue_free()
						if verbose:
							push_warning("[BlsquiSDK] Transaction EXPIRED on-chain.")
						return {"status": "EXPIRED", "error": "Transaction expired on-chain"}
			elif verbose:
				push_warning("[BlsquiSDK Poll] Non-200 HTTP response: %d" % response_code)

		# Wait interval before next poll frame
		await main_tree.create_timer(POLL_INTERVAL).timeout

	http_req.queue_free()
	if verbose:
		push_error("[BlsquiSDK] Transaction poll timed out after %s seconds." % TIMEOUT_SECONDS)
		
	return {"status": "TIMEOUT", "error": "Transaction poll timed out after %s seconds" % TIMEOUT_SECONDS}


static func generate_client_nonce() -> String:
	var crypto: Crypto = Crypto.new()
	# Use 32 random bytes (256 bits) of entropy for SHA-256
	var random_bytes: PackedByteArray = crypto.generate_random_bytes(32)
	
	# Generate SHA-256 lowercase 64-character hex string
	return Marshalls.raw_to_base64(random_bytes).to_lower().sha256_text()
