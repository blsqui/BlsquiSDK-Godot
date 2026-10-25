# Blsqui SDK for Godot Engine

The official Godot Engine SDK for **Blsqui** — enabling seamless Flow blockchain payments, Passkey wallet authentication, and microtransactions in Godot games.

## Features

- **Passkey & WebAuthn Ready:** Launches the system browser directly to the Blsqui Gateway for one-touch biometric signing.
- **Edge Polling Engine:** Asynchronous, non-blocking HTTP polling against Blsqui edge nodes until on-chain finality.
- **FLIX Native:** Built-in support for Flow Interaction Templates with arbitrary Cadence script parameters.

## 📦 Installation & Setup

1. Download or clone this repository.
2. Copy the `addons/blsqui_sdk/` directory into your project's `res://addons/` folder.
3. In the Godot Editor, navigate to **Project -> Project Settings -> Plugins** and enable **Blsqui SDK**.
4. That's it! `BlsquiSDK` is now available as a global singleton across all your scripts.

## Quick Start Example
Call `BlsquiSDK.request_transaction()` from any button or event handler:

See the complete sample in [`examples/car_movement.gd`](./examples/car_movement.gd).
```gdscript
extends Button

func _pressed() -> void:
    # Disable button during transaction
    disabled = true
    text = "Waiting for wallet..."

    var result: Dictionary = await BlsquiSDK.request_transaction({
        "is_testnet": true,
        "verbose": true,
        "flixId": '7d9d4b154547d7f6ec95e8b95741ed84663592d8c0016dbc4b28b6f9bf435ba5',
        "args": {
            "to": "0xa090f900023d6d34" # Merchant / game deposit address
        }
    })

    if result.status == "SEALED":
        print("🎉 Payment succeeded! TX ID: ", result.txId)
        print("Payer: ", result.payer)
        print("Amount Paid: ", result.amount, " ", result.token)
        # Unlock in-game item or grant access here
    else:
        push_warning("Payment unfinished. Status: %s | Error: %s" % [result.status, result.get("error", "")])

    disabled = false
    text = "Purchase Item"
```

## Configuration Reference
### `options` Dictionary
Pass these keys into `BlsquiSDK.request_transaction(options)`:
| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `is_testnet` | `boolean` | `true` | When `true`, connects to Flow Testnet (`lab.blsqui.net`). When `false`, connects to Flow Mainnet (`wallet.blsqui.net`). |
| `flix_id` | `String` | Default Fee Template | The FLIX (Flow Interaction Template) identifier. Defaults to the standard 10 FLOW entry template. |
| `args` | `Dictionary` | `{}` | Key-value arguments passed into the Cadence interaction. (e.g. `{"to": "0x..."}`). |
| `verbose` | `boolean` | `false` | When `true`, prints detailed polling requests and HTTP status logs to the Godot Output debugger. |

---

### `TransactionResult` Dictionary
Returned asynchronously by `await BlsquiSDK.request_transaction(...)`:

```gdscript
{
    "status": String,        # "SEALED" | "FAILED" | "EXPIRED" | "TIMEOUT" | "CANCELED"
    "txId": String,          # Flow blockchain transaction ID (SEALED only)
    "nonce": String,         # Cryptographic tracking nonce
    "payer": String,         # Flow account address that signed the transaction
    "to": String,            # Recipient account address (extracted from TokensDeposited)
    "amount": String,        # Executed payment amount (Cadence UFix64 string)
    "token": String,         # Token identifier (e.g., "FlowToken")
    "txFee": String,         # Gas/execution fee deducted on-chain (String or null)
    "error": String,         # Client-side error or failure description
    "errorMessage": Variant  # Detailed Cadence runtime error message from the node, or null
}
```

### Transaction Status Definitions

 - `SEALED`: The transaction was executed and finalized on the Flow blockchain.

 - `FAILED`: The transaction failed during on-chain execution (see errorMessage).

 - `EXPIRED`: The transaction expired on-chain before execution.

 - `TIMEOUT`: Polling exceeded the maximum duration (default: 300 seconds).

 - `CANCELED`: Polling was stopped manually via `BlsquiSDK.cancel_transaction()`.


## Querying Stage Slots (Cadence Access Node)

Query equipped in-game stage slots for any player on-demand directly from Flow Access Nodes. This executes purely via Cadence scripts over HTTP with zero WebRTC, no local wallet sign-in, and zero memory overhead.

See the complete sample in [`examples/scout_button.gd`](./examples/scout_button.gd).
```gdscript
func _on_scout_opponent_pressed(opponent_address: String) -> void:
    var slots: Array = await BlsquiSDK.get_stage_slots({
        "target_address": opponent_address,
        "publisher_address": "0xYourPublisherAddress",
        "app_id": "com_yourstudio_game",
        "is_testnet": true,
        "verbose": true
    })

    for slot: Dictionary in slots:
        print("Slot #%d -> Item ID: %s" % [slot["slotIndex"], slot["itemId"]])
```

## How to Access the Dashboard

Launching the dashboard establishes a direct WebRTC DataChannel connection with the wallet interface via Pion Hub. By passing a callback to summon_dashboard(), your game subscribes to real-time wallet events without polling—automatically receiving updates whenever the player logs in, modifies equipped stage slots, or completes on-chain item actions.

See the complete sample in [`examples/dashboard_button.gd`](./examples/dashboard_button.gd).
```
extends CharacterBody2D

func _ready() -> void:
	input_pickable = true

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_hub_button_pressed()

func _on_hub_button_pressed() -> void:
	BlsquiSDK.summon_dashboard("valkyrie-vanguard", "0x2f13c512df0b0ad7", "testnet", _on_blsqui_user_updated)

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
```

## Triggering In-Game Item Actions (WebRTC)

Trigger on-chain item actions directly from your gameplay runtime via real-time WebRTC DataChannels. The game client checks if the target item is actively equipped in the user's stage slots and dispatches an instant trigger signal to the wallet dashboard.

See the complete sample in [`examples/def_button.gd`](./examples/def_button.gd).
```gdscript
func _on_item_trigger_button_pressed() -> void:
	print("[Item Trigger Action Button] Pressed")

	if not BlsquiSDK.current_user:
		print("[Item Trigger Action Button] No active session. Open dashboard first.")
		return

	var slots: Array = BlsquiSDK.current_user.user_state.get("slot", [])
	var target_item_id: String = ""

	# Check if the item is currently equipped in any slot
	for slot: Dictionary in slots:
		var item_id: String = str(slot.get("itemId", ""))
		if item_id == TRIGGER_ITEM_ID:
			target_item_id = item_id
			break

	if target_item_id == "":
		print("[Item Trigger Action Button] Item is not equipped! Cannot trigger Item Trigger action.")
		return

	print("[Item Trigger Action Button] Activating item: ", target_item_id)
	BlsquiSDK.trigger_item_action(target_item_id)
```

## Requirements
- Godot Engine **4.x** (Standard or .NET)
- Active internet connection

## Prerequisites: WebRTC GDExtension
Before using WebRTC presence features on desktop platforms (macOS, Windows, Linux), you must install the official WebRTC GDExtension plugin:

1. Open Godot and navigate to the AssetLib tab at the top.

2. Search for WebRTC plugin (by Fabio Alessandrelli / faless).

3. Download and install it into your project root.

4. Restart the Godot editor (Project -> Reload Current Project).

(Alternatively, grab godot-extension-webrtc_native.zip from godotengine/webrtc-native Releases and place it under addons/webrtc or project root).

## License
MIT License - see [LICENSE](LICENSE) for details.
