extends CharacterBody2D

const SPEED = 400.0
var dialog_active: bool = false
var entry_completed: bool = false
var auto_driving_left: bool = false

@onready var tournament_dialog: ConfirmationDialog = $"../ConfirmationDialog"
@onready var loading_dialog: AcceptDialog = $"../LoadingDialog"

func _physics_process(_delta: float) -> void:
	# 🚗 Auto-drive sequence after successful entry confirmation
	if auto_driving_left:
		velocity = Vector2(-SPEED, 0)
		move_and_slide()
		return

	if dialog_active:
		return

	velocity = Vector2.ZERO

	if Input.is_action_pressed("ui_left"):
		velocity.x = -SPEED
	if Input.is_action_pressed("ui_right"):
		velocity.x = SPEED
	if Input.is_action_pressed("ui_up"):
		velocity.y = -SPEED
	if Input.is_action_pressed("ui_down"):
		velocity.y = SPEED

	move_and_slide()
	check_left_edge_trigger()

func check_left_edge_trigger() -> void:
	# Do not trigger if already paid or in dialog
	if entry_completed or auto_driving_left or dialog_active:
		return

	var left_edge: float = get_viewport_rect().position.x
	
	if global_position.x <= left_edge + 60:
		trigger_tournament_dialog()

func trigger_tournament_dialog() -> void:
	print("Godot: Showing popup.")
	dialog_active = true
	tournament_dialog.popup_centered()

func _on_confirmation_dialog_confirmed() -> void:
	tournament_dialog.hide()
	
	loading_dialog.dialog_text = "Browser opened. Please approve the payment in your browser..."
	loading_dialog.popup_centered()
		
	# 🚀 Await loopback receipt & on-chain SEALED status check
	#var result: Dictionary = await BlsquiSDK.request_transaction({
		#"is_testnet": true,
		#"verbose": true,
		#"flix_id": "7d9d4b154547d7f6ec95e8b95741ed84663592d8c0016dbc4b28b6f9bf435ba5",
		#"args": {
			#"to": "0xa090f900023d6d34"
		#}
	#})
	var result: Dictionary = await BlsquiSDK.request_transaction({
		"is_testnet": true,
		"verbose": true,
		"flixId": '7d9d4b154547d7f6ec95e8b95741ed84663592d8c0016dbc4b28b6f9bf435ba5',
		"args": {
			"to": "0xa090f900023d6d34" # deposit address
		}
	})
	## Close the loading dialog automatically once the SDK finishes polling
	if result.status == "SEALED":
		print("🎉 Payment succeeded! TX ID: ", result.txId)
		print("Payer: ", result.payer)
		print("Amount Paid: ", result.amount, " ", result.token)
		# Unlock in-game item or grant access here
	else:
		push_warning("Payment unfinished. Status: %s | Error: %s" % [result.status, result.get("error", "")])


func _on_confirmation_dialog_canceled() -> void:
	print("[GODOT] Tournament entry canceled.")
	global_position.x += 80 # Bounce car back from wall edge trigger
	dialog_active = false

func _on_loading_dialog_confirmed() -> void:
	dialog_active = false
	
	# 🏁 If entry was confirmed, start auto-driving the car past the left edge!
	if entry_completed:
		auto_driving_left = true
