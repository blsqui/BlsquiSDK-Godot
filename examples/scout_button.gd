extends CharacterBody2D

# Set your target player and publisher credentials here
const TARGET_ADDRESS: String = "0x2f13c512df0b0ad7"
const PUBLISHER_ADDRESS: String = "0x2f13c512df0b0ad7"
const APP_ID: String = "valkyrie-vanguard"

func _ready() -> void:
	# Enable input picking on this CharacterBody2D
	input_pickable = true

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		scout_opponent_slots()

func scout_opponent_slots() -> void:
	print("[Scout] Querying equipped slots for: ", TARGET_ADDRESS)

	var slots: Array = await BlsquiSDK.get_stage_slots({
		"target_address": TARGET_ADDRESS,
		"publisher_address": PUBLISHER_ADDRESS,
		"app_id": APP_ID,
		"is_testnet": true,
		"verbose": true
	})

	if slots.is_empty():
		print("[Scout] No items equipped or failed to query slots.")
		return

	print("===== [Scout] Opponent Stage Slots =====")
	for slot: Dictionary in slots:
		var slot_idx: int = slot.get("slotIndex", 0)
		var item_id: String = slot.get("itemId", "")
		print("Slot #%d -> Item ID: %s" % [slot_idx, item_id if item_id != "" else "(Empty)"])
	print("========================================")
