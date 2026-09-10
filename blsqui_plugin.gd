# blsqui_plugin.gd
@tool
extends EditorPlugin

func _enter_tree():
	# registers 'BlsquiSDK' globally.
	#add_autoload_singleton("BlsquiSDK", "res://addons/blsqui/blsqui_sdk.gd")
	pass

func _exit_tree():
	#remove_autoload_singleton("BlsquiSDK")
	pass