extends CharacterBody2D

const SHIELD_ITEM_ID: String = "shd_valkyrie_aegis_2"

func _ready() -> void:
	input_pickable = true

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_def_button_pressed()

func _on_def_button_pressed() -> void:
	print("[DEF Button] Pressed")

	if not BlsquiSDK.current_user:
		print("[DEF Button] No active session. Open dashboard first.")
		return

	var slots: Array = BlsquiSDK.current_user.user_state.get("slot", [])
	var target_item_id: String = ""

	# Check if the shield is currently equipped in any slot
	for slot: Dictionary in slots:
		var item_id: String = str(slot.get("itemId", ""))
		if item_id == SHIELD_ITEM_ID:
			target_item_id = item_id
			break

	if target_item_id == "":
		print("[DEF Button] Shield not equipped! Cannot trigger DEF action.")
		return

	print("[DEF Button] Activating shield: ", target_item_id)
	BlsquiSDK.trigger_item_action(target_item_id)
