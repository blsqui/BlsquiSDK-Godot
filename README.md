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

## How to Access to the Dashboard

Launching the dashboard establishes a direct WebRTC DataChannel connection with the wallet interface via Pion Hub. By passing a callback to summon_dashboard(), your game subscribes to real-time wallet events without polling—automatically receiving updates whenever the player logs in, modifies equipped stage slots, or completes on-chain item actions.

```
extends CharacterBody2D

func _ready() -> void:
	input_pickable = true

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_hub_button_pressed()

func _on_hub_button_pressed() -> void:
	print("[Dashboard] OPEN")
	BlsquiSDK.summon_dashboard("valkyrie-vanguard", "0x2f13c512df0b0ad7", "testnet", _on_blsqui_user_updated)

func _on_blsqui_user_updated(state: Dictionary) -> void:
	print("\n🎮 [Game Sync] User state received from Dashboard!")
	
	var is_logged_in: bool = bool(state.get("loggedIn", false))
	var player_addr: String = str(state.get("addr", ""))
	var user_name: String = str(state.get("userName", ""))
	var avatar_url: String = str(state.get("avatarImage", ""))
	var slots: Array = state.get("slot", [])

	print("Status:   ", "LOGGED IN" if is_logged_in else "GUEST / LOGGED OUT")
	print("Address:  ", player_addr)
	print("Username: ", user_name if user_name != "" else "(No display name)")
	print("Avatar:   ", avatar_url)
	print("Equipped items count: ", slots.size())

	# Inspect equipped stage slots (weapons, shields, abilities)
	for slot: Dictionary in slots:
		var slot_idx: int = int(slot.get("slotIndex", 0))
		var item_id: String = str(slot.get("itemId", ""))
		var item_name: String = str(slot.get("itemName", ""))
		var remaining_charges: int = int(slot.get("remainingCharges", 0))
		var max_charges: int = int(slot.get("maxCharges", 0))

		if item_id != "":
			print("  -> [Slot %d] %s (ID: %s) | Durability: %d / %d" % [
				slot_idx, item_name, item_id, remaining_charges, max_charges
			])
		else:
			print("  -> [Slot %d] Empty" % slot_idx)

	# Handle when an item's on-chain durability was just consumed
	var last_used: Variant = state.get("lastUsedItem", null)
	if last_used is Dictionary and not last_used.is_empty():
		print("⚡ Recent Item Action -> ID: %s | TX: %s" % [
			last_used.get("itemId", ""),
			last_used.get("txId", "")
		])
```

## Requirements
- Godot Engine **4.x** (Standard or .NET)
- Active internet connection

## License
MIT License - see [LICENSE](LICENSE) for details.
