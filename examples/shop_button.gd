class_name ShopButtonHandler
extends Button

const WEAPON_SHOP_FLIX_ID: String = "351d9d6f23ebe5ddbe9bf5b4f937a352c5caaa6a4439b5e464f3b16c1d671472"

@onready var loading_dialog: AcceptDialog = get_node_or_null("../LoadingDialog")

var _is_purchasing: bool = false

func _ready() -> void:
	pressed.connect(_on_shop_button_clicked)

func _on_shop_button_clicked() -> void:
	if _is_purchasing:
		return

	_is_purchasing = true
	disabled = true
	print("[Shop] Opening purchase transaction...")

	# Show transaction feedback in the dialog (matching car_movement.gd)
	if loading_dialog != null:
		loading_dialog.title = "Processing Shop Item..."
		loading_dialog.dialog_text = "Authorizing transaction on Flow...\nPlease complete payment in the browser."
		loading_dialog.popup_centered()

	# Configure transaction options matching Unity ShopButtonHandler
	var options: Dictionary = {
		"is_testnet": true,
		"verbose": true,
		"flix_id": WEAPON_SHOP_FLIX_ID,
		"args": {}
	}

	var result: Dictionary = await BlsquiSDK.request_transaction(options)

	# Update dialog state upon completion
	if result.get("status") == "SEALED":
		var tx_id: String = str(result.get("txId", ""))
		print("Shop purchase succeeded! TX ID: ", tx_id)
		if loading_dialog != null:
			loading_dialog.title = "Purchase Successful!"
			loading_dialog.dialog_text = "Item purchase sealed !!!\n\nTX ID:\n%s" % tx_id
			loading_dialog.popup_centered()
	else:
		var err_msg: String = str(result.get("errorMessage", ""))
		if err_msg == "" or err_msg == "<null>":
			err_msg = str(result.get("error", "Unknown error"))
		push_warning("[Shop] Purchase incomplete. Status: %s | Error: %s" % [result.get("status", "UNKNOWN"), err_msg])
		if loading_dialog != null:
			loading_dialog.title = "Transaction Cancelled"
			loading_dialog.dialog_text = "Status: %s\n%s" % [result.get("status", "UNKNOWN"), err_msg]
			loading_dialog.popup_centered()

	disabled = false
	_is_purchasing = false
