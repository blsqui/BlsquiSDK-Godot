class_name BlsquiStageSlot
extends RefCounted

const TESTNET_ACCESS_NODE: String = "https://rest-testnet.onflow.org/v1/scripts"
const MAINNET_ACCESS_NODE: String = "https://rest-mainnet.onflow.org/v1/scripts"

const SESAME_CONTRACT_TESTNET: String = "0x975b04756864e9ea"
const SESAME_CONTRACT_MAINNET: String = "0xb576a3926d239682"

const CADENCE_SCRIPT_TEMPLATE: String = """
import SesamePass from %s

access(all) fun main(publisher: Address, user: Address, appId: String): [String]? {
    return SesamePass.getUserItemSlots(publisher: publisher, user: user, appId: appId)
}
"""

## Queries equipped stage slots for a user via Flow Access Node REST API.
##
## @param options: Dictionary containing:
##    - "target_address": String (required, e.g. "0x01a2b3c4d5e6f7a8")
##    - "publisher_address": String (required, e.g. "0x1234567890abcdef")
##    - "app_id": String (optional, default: "")
##    - "is_testnet": bool (optional, default: true)
##    - "verbose": bool (optional, default: false)
##
## @returns Array[Dictionary] formatted like Web SDK:
##    [{"slotIndex": 1, "itemId": "item_123"}, ...]
static func get_stage_slots(options: Dictionary) -> Array:
	var is_testnet: bool = options.get("is_testnet", true)
	var verbose: bool = options.get("verbose", false)
	var target_addr: String = str(options.get("target_address", "")).strip_edges()
	var publisher_addr: String = str(options.get("publisher_address", "")).strip_edges()
	var app_id: String = str(options.get("app_id", ""))

	if target_addr == "" or publisher_addr == "":
		push_error("[BlsquiSDK] target_address and publisher_address are required.")
		return []

	var clean_target: String = target_addr if target_addr.begins_with("0x") else "0x" + target_addr
	var clean_publisher: String = publisher_addr if publisher_addr.begins_with("0x") else "0x" + publisher_addr

	var contract_addr: String = SESAME_CONTRACT_TESTNET if is_testnet else SESAME_CONTRACT_MAINNET
	var cadence_script: String = CADENCE_SCRIPT_TEMPLATE % contract_addr
	var script_b64: String = Marshalls.utf8_to_base64(cadence_script)

	var arg_pub_b64: String = Marshalls.utf8_to_base64(JSON.stringify({"type": "Address", "value": clean_publisher}))
	var arg_user_b64: String = Marshalls.utf8_to_base64(JSON.stringify({"type": "Address", "value": clean_target}))
	var arg_appid_b64: String = Marshalls.utf8_to_base64(JSON.stringify({"type": "String", "value": app_id}))

	var endpoint: String = TESTNET_ACCESS_NODE if is_testnet else MAINNET_ACCESS_NODE
	var payload: Dictionary = {
		"script": script_b64,
		"arguments": [arg_pub_b64, arg_user_b64, arg_appid_b64]
	}

	var main_tree: SceneTree = Engine.get_main_loop() as SceneTree
	var http_req: HTTPRequest = HTTPRequest.new()
	main_tree.root.add_child(http_req)

	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json"
	])

	var err: Error = http_req.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		http_req.queue_free()
		push_error("[BlsquiSDK] HTTPRequest setup failed: %d" % err)
		return []

	var response: Array = await http_req.request_completed
	http_req.queue_free()

	var response_code: int = response[1]
	var body_text: String = (response[3] as PackedByteArray).get_string_from_utf8()

	if response_code < 200 or response_code >= 300:
		if verbose:
			push_warning("[BlsquiSDK] Failed to query target slots (%d): %s" % [response_code, body_text])
		return []

	var json: JSON = JSON.new()
	if json.parse(body_text) != OK:
		push_error("[BlsquiSDK] Failed to parse Access Node JSON.")
		return []

	var cadence_res: Variant = json.get_data()

	# If the response itself is a base64-encoded string (or stringified JSON)
	if cadence_res is String:
		var raw_str: String = (cadence_res as String).strip_edges()
		# Try parsing directly in case it is double-stringified JSON
		if json.parse(raw_str) == OK:
			cadence_res = json.get_data()
		else:
			# Base64 decode to UTF-8 text and parse as JSON
			var decoded_bytes: PackedByteArray = Marshalls.base64_to_raw(raw_str)
			var decoded_text: String = decoded_bytes.get_string_from_utf8()
			if json.parse(decoded_text) == OK:
				cadence_res = json.get_data()

	if verbose:
		print("[BlsquiSDK] Decoded Cadence Object: ", cadence_res)

	var raw_array: Array = []

	# Traverse: Optional -> Array -> elements
	if cadence_res is Dictionary and cadence_res.has("value"):
		var inner_node: Variant = cadence_res.get("value")
		if inner_node is Dictionary and inner_node.has("value"):
			var array_node: Variant = inner_node.get("value")
			if array_node is Array:
				raw_array = array_node
		elif inner_node is Array:
			raw_array = inner_node

	var slots: Array = []
	for idx: int in range(raw_array.size()):
		var entry: Variant = raw_array[idx]
		var item_id: String = ""
		if entry is Dictionary and entry.has("value"):
			item_id = str(entry.get("value", ""))
		elif entry != null:
			item_id = str(entry)

		slots.append({
			"slotIndex": idx + 1,
			"itemId": item_id
		})

	if verbose:
		print("[BlsquiSDK] getStageSlots resolved: ", slots)

	return slots
