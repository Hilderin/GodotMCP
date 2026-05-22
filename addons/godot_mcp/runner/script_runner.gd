extends RefCounted

const GodotMcpApiScript := preload("godot_mcp_api.gd")

const MAX_SCRIPT_CHARS := 200000

const INVALID_SCRIPT := "INVALID_SCRIPT"
const SCRIPT_COMPILE_ERROR := "SCRIPT_COMPILE_ERROR"
const MISSING_RUN_METHOD := "MISSING_RUN_METHOD"
const SCRIPT_RUNTIME_ERROR := "SCRIPT_RUNTIME_ERROR"
const INVALID_RESULT := "INVALID_RESULT"

var _editor_interface: EditorInterface


func _init(editor_interface: EditorInterface = null) -> void:
	_editor_interface = editor_interface


func run(code: Variant, args: Variant = {}) -> Dictionary:
	if typeof(code) != TYPE_STRING:
		return _error(INVALID_SCRIPT, "Script code must be a string")

	var source: String = String(code)
	if source.strip_edges().is_empty():
		return _error(INVALID_SCRIPT, "Script code must not be empty")

	if source.length() > MAX_SCRIPT_CHARS:
		return _error(INVALID_SCRIPT, "Script code exceeds the maximum size", {
			"max_script_chars": MAX_SCRIPT_CHARS,
			"actual_script_chars": source.length(),
		})

	if not _has_ref_counted_extends(source):
		return _error(INVALID_SCRIPT, "Script must extend RefCounted")

	if not (args is Dictionary):
		return _error(INVALID_SCRIPT, "Script args must be a Dictionary")

	var script := GDScript.new()
	script.source_code = source
	var reload_error: Error = script.reload()
	if reload_error != OK:
		return _error(SCRIPT_COMPILE_ERROR, "Failed to compile GDScript", {
			"godot_error": int(reload_error),
		})

	var instance: Variant = script.new()
	if instance == null:
		return _error(SCRIPT_RUNTIME_ERROR, "Failed to instantiate script")

	if not instance.has_method("run"):
		return _error(MISSING_RUN_METHOD, "Script must define run(api, args)")

	var api := GodotMcpApiScript.new(_editor_interface)
	var raw_result: Variant = instance.call("run", api, args)
	return _normalize_result(raw_result)


func _has_ref_counted_extends(source: String) -> bool:
	for line in source.split("\n"):
		var stripped: String = String(line).strip_edges()
		if stripped.begins_with("#") or stripped.is_empty():
			continue
		return stripped == "extends RefCounted"
	return false


func _normalize_result(result: Variant) -> Dictionary:
	if not (result is Dictionary):
		return _error(INVALID_RESULT, "Script run() must return a Dictionary")

	if not result.has("ok") or typeof(result["ok"]) != TYPE_BOOL:
		return _error(INVALID_RESULT, "Script result must contain a boolean ok field")

	var normalized: Dictionary = result.duplicate(true)
	normalized["warnings"] = _normalize_warnings(normalized.get("warnings", []))
	if normalized["warnings"] == null:
		return _error(INVALID_RESULT, "Script result warnings must be an Array")

	if bool(normalized["ok"]):
		if not normalized.has("data"):
			normalized["data"] = {}
		if not (normalized["data"] is Dictionary):
			return _error(INVALID_RESULT, "Successful script result data must be a Dictionary")

		if not normalized.has("meta"):
			normalized["meta"] = {}
		if not (normalized["meta"] is Dictionary):
			return _error(INVALID_RESULT, "Script result meta must be a Dictionary")
	else:
		if not (normalized.get("error") is Dictionary):
			return _error(INVALID_RESULT, "Failed script result must contain an error Dictionary")

		var error: Dictionary = normalized["error"]
		if typeof(error.get("code")) != TYPE_STRING or String(error.get("code", "")).is_empty():
			return _error(INVALID_RESULT, "Script error must contain a non-empty code")
		if typeof(error.get("message")) != TYPE_STRING or String(error.get("message", "")).is_empty():
			return _error(INVALID_RESULT, "Script error must contain a non-empty message")
		if not error.has("details"):
			error["details"] = {}
		if not (error["details"] is Dictionary):
			return _error(INVALID_RESULT, "Script error details must be a Dictionary")
		if not normalized.has("meta"):
			normalized["meta"] = {}
		if not (normalized["meta"] is Dictionary):
			return _error(INVALID_RESULT, "Script result meta must be a Dictionary")

	if not _is_json_compatible(normalized):
		return _error(INVALID_RESULT, "Script result must be JSON-serializable")

	return normalized


func _normalize_warnings(warnings: Variant) -> Variant:
	if not (warnings is Array):
		return null
	return warnings


func _is_json_compatible(value: Variant, depth: int = 0) -> bool:
	if depth > 64:
		return false

	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for item in value:
				if not _is_json_compatible(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value.keys():
				if typeof(key) != TYPE_STRING:
					return false
				if not _is_json_compatible(value[key], depth + 1):
					return false
			return true
		_:
			return false


func _error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"error": {
			"code": code,
			"message": message,
			"details": details,
		},
		"warnings": [],
		"meta": {},
	}
