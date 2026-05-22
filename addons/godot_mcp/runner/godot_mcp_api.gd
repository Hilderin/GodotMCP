class_name GodotMcpApi
extends RefCounted


var _editor_interface: EditorInterface
var _warnings: Array = []


func _init(editor_interface: EditorInterface = null) -> void:
	_editor_interface = editor_interface


func success(data: Dictionary = {}, meta: Dictionary = {}) -> Dictionary:
	return {
		"ok": true,
		"data": data,
		"warnings": _warnings.duplicate(true),
		"meta": meta,
	}


func error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"error": {
			"code": code,
			"message": message,
			"details": details,
		},
		"warnings": _warnings.duplicate(true),
		"meta": {},
	}


func warning(message: String, details: Dictionary = {}) -> void:
	_warnings.append({
		"message": message,
		"details": details,
	})


func get_editor_interface() -> EditorInterface:
	return _editor_interface
