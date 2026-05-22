extends RefCounted

const JsonRpc := preload("../utils/json_rpc.gd")
const ScriptRunner := preload("../runner/script_runner.gd")
const GodotMcpApiScript := preload("../runner/godot_mcp_api.gd")

const PROTOCOL_VERSION := "2024-11-05"

var _tool_registry
var _script_runner
var _editor_interface: EditorInterface
var _log_buffer = null


func _init(tool_registry, editor_interface: EditorInterface = null, log_buffer = null) -> void:
	_tool_registry = tool_registry
	_editor_interface = editor_interface
	_log_buffer = log_buffer
	_ensure_script_runner()


func parse_error(message: String) -> Dictionary:
	return JsonRpc.error(null, JsonRpc.PARSE_ERROR, message)


func handle(payload: Variant) -> Dictionary:
	if payload is Array:
		return _handle_batch(payload)

	var response: Variant = _handle_single(payload)
	return {
		"has_response": response != null,
		"response": response,
	}


func _handle_batch(payload: Array) -> Dictionary:
	if payload.is_empty():
		return {
			"has_response": true,
			"response": JsonRpc.error(null, JsonRpc.INVALID_REQUEST, "Invalid JSON-RPC batch"),
		}

	var responses: Array = []
	for item in payload:
		var response: Variant = _handle_single(item)
		if response != null:
			responses.append(response)

	return {
		"has_response": not responses.is_empty(),
		"response": responses,
	}


func _handle_single(request: Variant) -> Variant:
	if not (request is Dictionary):
		return JsonRpc.error(null, JsonRpc.INVALID_REQUEST, "Invalid JSON-RPC request")

	var id: Variant = request.get("id", null)
	var has_id: bool = request.has("id")

	if request.get("jsonrpc", "") != "2.0":
		return JsonRpc.error(id if has_id else null, JsonRpc.INVALID_REQUEST, "Invalid JSON-RPC version")

	if not request.has("method") or typeof(request["method"]) != TYPE_STRING:
		return JsonRpc.error(id if has_id else null, JsonRpc.INVALID_REQUEST, "Missing JSON-RPC method")

	if has_id and not JsonRpc.is_valid_id(id):
		return JsonRpc.error(null, JsonRpc.INVALID_REQUEST, "Invalid JSON-RPC id")

	var method: String = String(request["method"])
	var params: Variant = request.get("params", {})
	var result: Dictionary = _dispatch(method, params)

	if not has_id:
		return null

	if result.has("error"):
		return JsonRpc.error(id, int(result["error"].get("code", JsonRpc.INTERNAL_ERROR)), String(result["error"].get("message", "Internal error")), result["error"].get("data", null))

	return JsonRpc.result(id, result.get("result", {}))


func _dispatch(method: String, params: Variant) -> Dictionary:
	match method:
		"initialize":
			return {"result": _initialize_result(params)}
		"notifications/initialized":
			return {"result": {}}
		"ping":
			return {"result": {}}
		"tools/list":
			return {"result": {"tools": _tool_registry.list_tools()}}
		"tools/call":
			return _tool_call(params)
		_:
			return {"error": {"code": JsonRpc.METHOD_NOT_FOUND, "message": "Method not found: %s" % method}}


func _initialize_result(_params: Variant) -> Dictionary:
	return {
		"protocolVersion": PROTOCOL_VERSION,
		"capabilities": {
			"tools": {
				"listChanged": false,
			},
		},
		"serverInfo": {
			"name": "godot-mcp",
			"version": "0.1.0",
		},
	}


func _tool_call(params: Variant) -> Dictionary:
	if not (params is Dictionary):
		return {"error": {"code": JsonRpc.INVALID_PARAMS, "message": "Tool call params must be an object"}}

	var tool_name: String = ""
	tool_name = String(params.get("name", ""))

	if tool_name.is_empty():
		return {"error": {"code": JsonRpc.INVALID_PARAMS, "message": "Missing tool name"}}

	if not _tool_registry.has_tool(tool_name):
		return {"error": {"code": JsonRpc.INVALID_PARAMS, "message": "Unknown tool: %s" % tool_name}}

	var arguments: Variant = params.get("arguments", {})
	if not (arguments is Dictionary):
		return {"error": {"code": JsonRpc.INVALID_PARAMS, "message": "Tool arguments must be an object"}}

	if tool_name == "execute_editor_script":
		_ensure_script_runner()
		var runner_result: Dictionary = _script_runner.run(arguments.get("code", null), arguments.get("args", {}))
		return {"result": _tool_result(runner_result)}

	if tool_name == "get_logs":
		return {"result": _tool_result(_get_logs(arguments))}

	if tool_name == "get_editor_state":
		return {"result": _tool_result(_get_editor_state())}

	if tool_name == "get_scene_snapshot":
		return {"result": _tool_result(_get_scene_snapshot(arguments))}

	if tool_name == "run_project":
		return {"result": _tool_result(_run_project(arguments))}

	if tool_name == "stop_project":
		return {"result": _tool_result(_stop_project())}

	if tool_name == "capture_screenshot":
		return {"result": _capture_screenshot(arguments)}

	return {
		"error": {
			"code": JsonRpc.INTERNAL_ERROR,
			"message": "Tool execution is not implemented before later phases: %s" % tool_name,
		}
	}


func _tool_result(result: Dictionary) -> Dictionary:
	return {
		"content": [
			{
				"type": "text",
				"text": JSON.stringify(result),
			}
		],
		"structuredContent": result,
		"isError": not bool(result.get("ok", false)),
	}


func _get_editor_state() -> Dictionary:
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		return _tool_error("EDITOR_UNAVAILABLE", "EditorInterface is not available")

	var scene = editor_interface.get_edited_scene_root()
	var selection_paths := []
	var selection = editor_interface.get_selection()
	if selection != null:
		for node in selection.get_selected_nodes():
			if node is Node:
				selection_paths.append(_scene_node_path(node, scene))

	return _tool_success({
		"godot_version": Engine.get_version_info().get("string", ""),
		"editor_path": OS.get_executable_path(),
		"project_path": ProjectSettings.globalize_path("res://"),
		"current_scene_path": scene.scene_file_path if scene != null else "",
		"current_scene_name": scene.name if scene != null else "",
		"selection": selection_paths,
		"is_playing": editor_interface.is_playing_scene(),
		"playing_scene": editor_interface.get_playing_scene() if editor_interface.is_playing_scene() else "",
	})


func _get_scene_snapshot(arguments: Dictionary) -> Dictionary:
	var api = GodotMcpApiScript.new(_get_editor_interface())
	var include_properties := bool(arguments.get("include_properties", false))
	var max_depth := int(arguments.get("max_depth", 32))
	return api.success(api.get_scene_tree_snapshot(null, max_depth, include_properties))


func _get_logs(arguments: Dictionary) -> Dictionary:
	if _log_buffer == null:
		return _tool_error("LOG_BUFFER_UNAVAILABLE", "Console log buffer is not available")

	var source := String(arguments.get("source", ""))
	var level := String(arguments.get("level", ""))
	var limit := int(arguments.get("limit", 0))
	return _tool_success({
		"entries": _log_buffer.get_entries(source, limit, level),
	})


func _run_project(arguments: Dictionary) -> Dictionary:
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		return _tool_error("EDITOR_UNAVAILABLE", "EditorInterface is not available")

	var scene_path := String(arguments.get("scene_path", "")).strip_edges()
	if scene_path.is_empty():
		var main_scene := String(ProjectSettings.get_setting("application/run/main_scene", ""))
		if main_scene.is_empty():
			return _tool_error("MAIN_SCENE_NOT_CONFIGURED", "No main scene is configured; pass scene_path or set application/run/main_scene")
		if not FileAccess.file_exists(main_scene):
			return _tool_error("MAIN_SCENE_NOT_FOUND", "Configured main scene file does not exist", {"scene_path": main_scene})
		editor_interface.play_main_scene()
	else:
		if not scene_path.begins_with("res://"):
			return _tool_error("INVALID_SCENE_PATH", "scene_path must be empty or a res:// path", {"scene_path": scene_path})
		if not FileAccess.file_exists(scene_path):
			return _tool_error("SCENE_NOT_FOUND", "Scene file does not exist", {"scene_path": scene_path})
		editor_interface.play_custom_scene(scene_path)

	return _tool_success({
		"is_playing": editor_interface.is_playing_scene(),
		"scene_path": editor_interface.get_playing_scene() if editor_interface.is_playing_scene() else scene_path,
	})


func _stop_project() -> Dictionary:
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		return _tool_error("EDITOR_UNAVAILABLE", "EditorInterface is not available")

	if editor_interface.is_playing_scene():
		editor_interface.stop_playing_scene()

	return _tool_success({
		"is_playing": editor_interface.is_playing_scene(),
	})


func _tool_success(data: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"data": data,
		"warnings": [],
		"meta": {},
	}


func _tool_error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
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


func _get_editor_interface():
	if _editor_interface != null:
		return _editor_interface
	if Engine.has_singleton("EditorInterface"):
		return Engine.get_singleton("EditorInterface")
	return null


func _scene_node_path(node: Node, scene_root: Node) -> String:
	if scene_root != null and node == scene_root:
		return "/%s" % scene_root.name
	if scene_root != null and scene_root.is_ancestor_of(node):
		return "/%s/%s" % [scene_root.name, str(scene_root.get_path_to(node))]
	return str(node.get_path())


func _ensure_script_runner() -> void:
	if _script_runner == null:
		_script_runner = ScriptRunner.new(_editor_interface, _log_buffer)


func _capture_screenshot(arguments: Dictionary) -> Dictionary:
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		return _mcp_error_result("EDITOR_UNAVAILABLE", "EditorInterface is not available")

	var return_mode := String(arguments.get("return_mode", "base64"))
	var area := String(arguments.get("area", "editor"))

	var image := _capture_editor_viewport(editor_interface, area)
	if image == null or image.is_empty():
		return _mcp_error_result("CAPTURE_FAILED", "Failed to capture editor viewport")

	var width := image.get_width()
	var height := image.get_height()

	if return_mode == "path":
		var output_dir := String(arguments.get("output_dir", "")).strip_edges()
		if output_dir.is_empty():
			output_dir = OS.get_temp_dir()

		var datetime := Time.get_datetime_dict_from_system()
		var timestamp := "%d-%02d-%02d_%02d-%02d-%02d" % [
			datetime.year, datetime.month, datetime.day,
			datetime.hour, datetime.minute, datetime.second,
		]
		var file_path := output_dir.path_join("godot_screenshot_%s.png" % timestamp)
		var save_error := image.save_png(file_path)
		if save_error != OK:
			return _mcp_error_result("SAVE_FAILED", "Failed to save screenshot to disk", {
				"path": file_path,
				"godot_error": int(save_error),
			})
		return _mcp_text_result({
			"file_path": ProjectSettings.globalize_path(file_path),
			"width": width,
			"height": height,
			"format": "png",
			"area": area,
		})
	else:
		var png_bytes := image.save_png_to_buffer()
		var b64 := Marshalls.raw_to_base64(png_bytes)
		return _mcp_image_result(b64, width, height, area)


func _capture_editor_viewport(editor_interface: EditorInterface, area: String) -> Image:
	var base_control = editor_interface.get_base_control()
	if base_control == null:
		return null

	var viewport: Viewport
	if area == "viewport":
		var sub_viewport = editor_interface.get_editor_viewport_3d()
		if sub_viewport != null:
			viewport = sub_viewport

	if viewport == null:
		viewport = base_control.get_viewport()

	if viewport == null:
		return null

	return viewport.get_texture().get_image()


func _mcp_text_result(data: Dictionary) -> Dictionary:
	return {
		"content": [
			{
				"type": "text",
				"text": JSON.stringify({"ok": true, "data": data}),
			},
		],
		"isError": false,
	}


func _mcp_image_result(b64: String, width: int, height: int, area: String) -> Dictionary:
	return {
		"content": [
			{
				"type": "text",
				"text": JSON.stringify({
					"ok": true,
					"data": {
						"width": width,
						"height": height,
						"area": area,
						"format": "png",
					},
				}),
			},
			{
				"type": "image",
				"data": b64,
				"mimeType": "image/png",
			},
		],
		"isError": false,
	}


func _mcp_error_result(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {
		"content": [
			{
				"type": "text",
				"text": JSON.stringify({
					"ok": false,
					"error": {
						"code": code,
						"message": message,
						"details": details,
					},
				}),
			},
		],
		"isError": true,
	}
