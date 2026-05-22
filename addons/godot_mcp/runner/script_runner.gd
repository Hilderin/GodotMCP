extends RefCounted

const GodotMcpApiScript := preload("godot_mcp_api.gd")

const MAX_SCRIPT_CHARS := 200000

const INVALID_SCRIPT := "INVALID_SCRIPT"
const SCRIPT_COMPILE_ERROR := "SCRIPT_COMPILE_ERROR"
const MISSING_RUN_METHOD := "MISSING_RUN_METHOD"
const SCRIPT_RUNTIME_ERROR := "SCRIPT_RUNTIME_ERROR"
const INVALID_RESULT := "INVALID_RESULT"

var _editor_interface: EditorInterface
var _log_buffer = null


func _init(editor_interface: EditorInterface = null, log_buffer = null) -> void:
	_editor_interface = editor_interface
	_log_buffer = log_buffer


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

	var compile_log_cursor := _log_cursor()
	var script := GDScript.new()
	script.source_code = source
	var reload_error: Error = script.reload()
	if reload_error != OK:
		return _error(SCRIPT_COMPILE_ERROR, "Failed to compile GDScript", _details_with_logs({
			"godot_error": int(reload_error),
		}, compile_log_cursor))

	var runtime_log_cursor := _log_cursor()
	var instance: Variant = script.new()
	if instance == null:
		return _error(SCRIPT_RUNTIME_ERROR, "Failed to instantiate script", _details_with_logs({}, runtime_log_cursor))

	if not instance.has_method("run"):
		return _error(MISSING_RUN_METHOD, "Script must define run(api, args)")

	var api := GodotMcpApiScript.new(_editor_interface)
	runtime_log_cursor = _log_cursor()
	var raw_result: Variant = instance.call("run", api, args)
	return _normalize_result(raw_result, _new_error_logs(runtime_log_cursor))


func _has_ref_counted_extends(source: String) -> bool:
	for line in source.split("\n"):
		var stripped: String = String(line).strip_edges()
		if stripped.begins_with("#") or stripped.is_empty():
			continue
		return stripped == "extends RefCounted"
	return false


func _normalize_result(result: Variant, error_logs: Array = []) -> Dictionary:
	if not (result is Dictionary):
		return _error(INVALID_RESULT, "Script run() must return a Dictionary", _logs_details(error_logs))

	if not result.has("ok") or typeof(result["ok"]) != TYPE_BOOL:
		return _error(INVALID_RESULT, "Script result must contain a boolean ok field", _logs_details(error_logs))

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


func _log_cursor() -> int:
	if _log_buffer != null and _log_buffer.has_method("get_cursor"):
		return int(_log_buffer.get_cursor())
	return -1


func _new_error_logs(cursor: int) -> Array:
	if cursor < 0 or _log_buffer == null or not _log_buffer.has_method("get_entries_since"):
		return []
	return _log_buffer.get_entries_since(cursor, "editor", "error")


func _details_with_logs(details: Dictionary, cursor: int) -> Dictionary:
	var normalized := details.duplicate(true)
	var logs := _new_error_logs(cursor)
	if not logs.is_empty():
		normalized["logs"] = logs
	return normalized


func _logs_details(logs: Array) -> Dictionary:
	if logs.is_empty():
		return {}
	return {"logs": logs}


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
