# Blsqui SDK for Godot Engine

The official Godot Engine SDK for **Blsqui** — enabling seamless Flow blockchain Web-RPC transactions and in-game payment dialogs.

## Features
- **Local Loopback Auth:** Secure, browser-based Flow wallet authentication via local loopback.
- **Cloudflare Worker Backbone:** High-throughput, edge-accelerated transaction indexing and status polling via Cloudflare Workers.
- **Pre-built UI Nodes:** Ready-to-use payment confirmation and transaction loading dialogs.
- **Asynchronous Signals:** Built-in signals (`transaction_completed`, `payment_failed`) for clean game loop control.

## 📦 Quick Start
1. Clone or download this reposit_ory.
2. Copy the `addons/blsqui_sdk/` directory into your Godot project's `res://addons/` folder.
3. Enable the **Blsqui SDK** plugin in **Project Settings -> Plugins**.
4. Add the `BlsquiManager` node to your scene.

## Requirements
- Godot Engine **4.x** (Standard or .NET)
- Active internet connection for Web-RPC polling

## License
MIT License - see [LICENSE](LICENSE) for details.
