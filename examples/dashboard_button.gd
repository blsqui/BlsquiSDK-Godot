extends CharacterBody2D

# Point to your on-screen HUD label (adjust path if needed)
@onready var sync_status_label: Label = get_node_or_null("../HUDLayer/SyncHUDPanel/SyncStatusLabel")

func _ready() -> void:
	input_pickable = true
	_setup_hud_style()

func _setup_hud_style() -> void:
	if not sync_status_label:
		return
	
	# Label configuration
	sync_status_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	sync_status_label.add_theme_color_override("font_color", Color.WHITE)
	sync_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sync_status_label.text = "⚡ [WebRTC Idle] Click HUB to Connect"

	# panel styling
	var parent_panel = sync_status_label.get_parent() as Control
	if parent_panel:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(0.09, 0.10, 0.13, 0.98)
		style.border_color = Color(0.35, 0.4, 0.5, 0.4)
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 10
		style.content_margin_bottom = 220
		parent_panel.add_theme_stylebox_override("panel", style)

		parent_panel.custom_minimum_size = Vector2(360, 120)

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_hub_button_pressed()

func _on_hub_button_pressed() -> void:
	print("[Dashboard] OPEN")
	BlsquiSDK.summon_dashboard("valkyrie-vanguard", "0x2f13c512df0b0ad7", "testnet", _on_blsqui_user_updated)

func _flash_action_feedback() -> void:
	if not sync_status_label:
		return
	var parent_panel: Control = sync_status_label.get_parent() as Control
	if not parent_panel:
		return

	var tween: Tween = create_tween()
	tween.tween_method(func(col: Color):
		var style: StyleBoxFlat = parent_panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			style.border_color = col
	, Color(1.0, 0.82, 0.2, 1.0), Color(0.35, 0.4, 0.5, 0.4), 1.0)

func _on_blsqui_user_updated(state: Dictionary) -> void:
	if not sync_status_label:
		return

	# Handle interim connection status text
	if state.has("status_text"):
		sync_status_label.text = "⚡ %s" % state["status_text"]
		return

	var is_logged_in: bool = bool(state.get("loggedIn", false))
	var player_addr: String = str(state.get("addr", ""))
	var user_name: String = str(state.get("userName", ""))
	var slots: Array = state.get("slot", [])
	var time_str: String = Time.get_time_string_from_system()

	var hud_text: String = "⚡ [WebRTC SYNC - %s]\n" % time_str
	hud_text += "• Status: %s" % ("LOGGED IN" if is_logged_in else "GUEST / OFFLINE")
	
	if is_logged_in:
		var short_addr: String = player_addr.left(6) + "..." + player_addr.right(4) if player_addr.length() > 10 else player_addr
		hud_text += " | %s (%s)\n" % [user_name if user_name != "" else "Anon", short_addr]
	else:
		hud_text += "\n"

	var active_item_count: int = 0
	for slot: Dictionary in slots:
		var idx: int = int(slot.get("slotIndex", 0))
		var item_id: String = str(slot.get("itemId", ""))
		var item_name: String = str(slot.get("itemName", ""))
		
		# Fallback to 3 if null or 0
		var remaining_charges: int = int(slot.get("remainingCharges", 3))
		if remaining_charges <= 0:
			remaining_charges = 3
			
		var max_charges: int = int(slot.get("maxCharges", 3))
		if max_charges <= 0:
			max_charges = 3

		if item_id != "":
			active_item_count += 1
			# Formats like: [1] Dragon Piercer (3 / 5)
			hud_text += "  [%d] %s (%d / %d)\n" % [idx, item_name, remaining_charges, max_charges]

	if active_item_count == 0:
		hud_text += "  (No items equipped)\n"

	# Check for last item use action and highlight prominently
	var last_used: Variant = state.get("lastUsedItem", null)
	if last_used is Dictionary and not last_used.is_empty():
		var used_id: String = str(last_used.get("itemId", ""))
		var tx_hash: String = str(last_used.get("txId", "")).left(8)
		hud_text += "🔥 ITEM USED 🔥: %s (TX: %s...)\n" % [used_id, tx_hash]
		_flash_action_feedback()

	sync_status_label.text = hud_text.strip_edges(false, true)
