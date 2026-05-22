extends Logger

const DEFAULT_MAX_ENTRIES := 500

var max_entries: int = DEFAULT_MAX_ENTRIES
var _entries: Array = []


func _log_message(message: String, error: bool) -> void:
	_append({
		"level": "error" if error else "info",
		"source": "console",
		"message": message,
		"time": Time.get_datetime_string_from_system(false, true),
		"details": {},
	})


func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array) -> void:
	var message := code
	if not rationale.is_empty():
		message = "%s: %s" % [code, rationale]

	_append({
		"level": _level_from_error_type(error_type),
		"source": "console",
		"message": message,
		"time": Time.get_datetime_string_from_system(false, true),
		"details": {
			"function": function,
			"file": file,
			"line": line,
			"code": code,
			"rationale": rationale,
			"editor_notify": editor_notify,
			"error_type": error_type,
			"script_backtraces": _stringify_backtraces(script_backtraces),
		},
	})


func get_entries(source: String = "", limit: int = 0, level: String = "") -> Array:
	var normalized_limit: int = max_entries if limit <= 0 else clampi(limit, 1, max_entries)
	var normalized_source := source.strip_edges().to_lower()
	if normalized_source == "editor":
		normalized_source = "console"
	elif normalized_source == "all":
		normalized_source = ""

	var normalized_level := level.strip_edges().to_lower()
	if normalized_level == "all":
		normalized_level = ""

	var filtered: Array = []
	for index in range(_entries.size() - 1, -1, -1):
		var entry: Dictionary = _entries[index]
		if not normalized_source.is_empty() and String(entry.get("source", "")) != normalized_source:
			continue
		if not normalized_level.is_empty() and String(entry.get("level", "")) != normalized_level:
			continue
		filtered.push_front(entry.duplicate(true))
		if filtered.size() >= normalized_limit:
			break
	return filtered


func clear() -> void:
	_entries.clear()


func _append(entry: Dictionary) -> void:
	_entries.append(entry)
	while _entries.size() > max_entries:
		_entries.remove_at(0)


func _stringify_backtraces(script_backtraces: Array) -> Array:
	var result: Array = []
	for backtrace in script_backtraces:
		result.append(str(backtrace))
	return result


func _level_from_error_type(error_type: int) -> String:
	return "warning" if error_type == 1 else "error"
