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


func handle_async(payload: Variant, callback: Callable) -> void:
	if payload is Array:
		_handle_batch_async(payload, callback)
		return

	_handle_single_async(payload, func(response: Variant) -> void:
		callback.call({
			"has_response": response != null,
			"response": response,
		})
	)


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


func _handle_batch_async(payload: Array, callback: Callable) -> void:
	if payload.is_empty():
		callback.call({
			"has_response": true,
			"response": JsonRpc.error(null, JsonRpc.INVALID_REQUEST, "Invalid JSON-RPC batch"),
		})
		return

	_handle_batch_item_async(payload, 0, [], callback)


func _handle_batch_item_async(payload: Array, index: int, responses: Array, callback: Callable) -> void:
	if index >= payload.size():
		callback.call({
			"has_response": not responses.is_empty(),
			"response": responses,
		})
		return

	_handle_single_async(payload[index], func(response: Variant) -> void:
		if response != null:
			responses.append(response)
		_handle_batch_item_async(payload, index + 1, responses, callback)
	)


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


func _handle_single_async(request: Variant, callback: Callable) -> void:
	if not (request is Dictionary):
		callback.call(JsonRpc.error(null, JsonRpc.INVALID_REQUEST, "Invalid JSON-RPC request"))
		return

	var id: Variant = request.get("id", null)
	var has_id: bool = request.has("id")

	if request.get("jsonrpc", "") != "2.0":
		callback.call(JsonRpc.error(id if has_id else null, JsonRpc.INVALID_REQUEST, "Invalid JSON-RPC version"))
		return

	if not request.has("method") or typeof(request["method"]) != TYPE_STRING:
		callback.call(JsonRpc.error(id if has_id else null, JsonRpc.INVALID_REQUEST, "Missing JSON-RPC method"))
		return

	if has_id and not JsonRpc.is_valid_id(id):
		callback.call(JsonRpc.error(null, JsonRpc.INVALID_REQUEST, "Invalid JSON-RPC id"))
		return

	var method: String = String(request["method"])
	var params: Variant = request.get("params", {})
	_dispatch_async(method, params, func(result: Dictionary) -> void:
		if not has_id:
			callback.call(null)
			return

		if result.has("error"):
			callback.call(JsonRpc.error(id, int(result["error"].get("code", JsonRpc.INTERNAL_ERROR)), String(result["error"].get("message", "Internal error")), result["error"].get("data", null)))
			return

		callback.call(JsonRpc.result(id, result.get("result", {})))
	)


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


func _dispatch_async(method: String, params: Variant, callback: Callable) -> void:
	if method == "tools/call":
		_tool_call_async(params, callback)
		return

	callback.call(_dispatch(method, params))


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

	if tool_name == "get_documentation":
		return {"result": _tool_result(_get_documentation(arguments))}

	if tool_name == "capture_screenshot":
		return {"result": _capture_screenshot(arguments)}

	if tool_name == "get_resource":
		return {"result": _tool_result(_get_resource(arguments))}

	return {
		"error": {
			"code": JsonRpc.INTERNAL_ERROR,
			"message": "Tool execution is not implemented before later phases: %s" % tool_name,
		}
	}


func _tool_call_async(params: Variant, callback: Callable) -> void:
	if not (params is Dictionary):
		callback.call({"error": {"code": JsonRpc.INVALID_PARAMS, "message": "Tool call params must be an object"}})
		return

	var tool_name: String = ""
	tool_name = String(params.get("name", ""))

	if tool_name.is_empty():
		callback.call({"error": {"code": JsonRpc.INVALID_PARAMS, "message": "Missing tool name"}})
		return

	if not _tool_registry.has_tool(tool_name):
		callback.call({"error": {"code": JsonRpc.INVALID_PARAMS, "message": "Unknown tool: %s" % tool_name}})
		return

	var arguments: Variant = params.get("arguments", {})
	if not (arguments is Dictionary):
		callback.call({"error": {"code": JsonRpc.INVALID_PARAMS, "message": "Tool arguments must be an object"}})
		return

	if tool_name == "execute_editor_script":
		_ensure_script_runner()
		_script_runner.run_deferred(arguments.get("code", null), arguments.get("args", {}), func(runner_result: Dictionary) -> void:
			callback.call({"result": _tool_result(runner_result)})
		)
		return

	callback.call(_tool_call(params))


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
	var root_path := String(arguments.get("path", ""))
	var max_length := int(arguments.get("max_length", 0))
	return api.success(api.get_scene_tree_snapshot(null, max_depth, include_properties, root_path, max_length))


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


func _get_documentation(arguments: Dictionary) -> Dictionary:
	var cls_name := String(arguments.get("class_name", "")).strip_edges()
	if cls_name.is_empty():
		return _tool_error("INVALID_PARAMS", "class_name is required")

	if not ClassDB.class_exists(cls_name):
		return _tool_error("CLASS_NOT_FOUND", "Class '%s' does not exist in ClassDB. Built-in types (String, int, float, Vector2, etc.) are not registered in ClassDB." % cls_name)

	var filter := String(arguments.get("filter", ""))
	var include_arg := arguments.get("include", null)
	var include_inherited := bool(arguments.get("include_inherited", false))
	var sections := _resolve_doc_sections(include_arg)
	var no_inheritance := not include_inherited

	var result := {
		"name": cls_name,
		"inherits": ClassDB.get_parent_class(cls_name),
		"inheritance_chain": _inheritance_chain(cls_name),
	}	

	var doc_info = _load_doc_class_info(cls_name)
	if doc_info != null:
		result["brief_description"] = String(doc_info.get("brief_description", ""))
		var desc := String(doc_info.get("description", ""))
		if not desc.is_empty():
			result["description"] = desc
		var tutorials = doc_info.get("tutorials", [])
		if tutorials is Array and not tutorials.is_empty():
			result["tutorials"] = tutorials

	if "methods" in sections:
		result["methods"] = _doc_methods(cls_name, filter, no_inheritance, doc_info)
	if "properties" in sections:
		result["properties"] = _doc_properties(cls_name, filter, no_inheritance, doc_info)
	if "signals" in sections:
		result["signals"] = _doc_signals(cls_name, filter, no_inheritance, doc_info)
	if "constants" in sections:
		result["constants"] = _doc_constants(cls_name, filter, no_inheritance, doc_info)

	return _tool_success(result)


func _resolve_doc_sections(include_arg) -> Array:
	var defaults := ["methods", "properties", "signals", "constants"]
	if include_arg == null:
		return defaults
	if typeof(include_arg) != TYPE_ARRAY:
		return defaults
	var result := []
	for s in include_arg:
		if typeof(s) == TYPE_STRING and defaults.has(s):
			result.append(String(s))
	return result if not result.is_empty() else defaults


func _inheritance_chain(cls_name: String) -> Array:
	var chain := []
	var current := cls_name
	while not current.is_empty():
		chain.append(current)
		current = ClassDB.get_parent_class(current)
	return chain


func _load_doc_class_info(cls_name: String):
	if not ClassDB.class_exists("DocData"):
		return null
	var dd = ClassDB.instantiate("DocData")
	if dd == null or not dd.has_method("load_doc_classes"):
		return null
	dd.load_doc_classes()
	if not dd.has("class_list"):
		return null
	var class_list = dd.get("class_list")
	if class_list == null or not (class_list is Dictionary):
		return null
	return class_list.get(cls_name, null)


func _variant_type_str(type_code: int, class_hint: String = "") -> String:
	if type_code == TYPE_OBJECT and not class_hint.is_empty():
		return class_hint
	if type_code == TYPE_NIL:
		return "void"
	return type_string(type_code)


func _doc_args(args: Array) -> Array:
	var result := []
	for a in args:
		if not (a is Dictionary):
			continue
		var entry := {
			"name": String(a.get("name", "")),
			"type": _variant_type_str(int(a.get("type", TYPE_NIL)), String(a.get("class_name", ""))),
		}
		if a.get("has_default_value", false):
			entry["default"] = String(a.get("default", ""))
		result.append(entry)
	return result


func _matches_filter(name: String, filter: String, doc_entry: Dictionary = {}) -> bool:
	if filter.is_empty():
		return true
	if name.match(filter):
		return true
	if doc_entry.has("description"):
		var desc := String(doc_entry["description"])
		if not desc.is_empty() and desc.match(filter):
			return true
	return false


func _build_doc_lookup(doc_info, section: String) -> Dictionary:
	var lookup := {}
	if doc_info == null or not doc_info.has(section):
		return lookup
	for entry in doc_info.get(section, []):
		if entry is Dictionary:
			lookup[String(entry.get("name", ""))] = entry
	return lookup


func _doc_methods(cls_name: String, filter: String, no_inheritance: bool, doc_info) -> Array:
	var raw := ClassDB.class_get_method_list(cls_name, no_inheritance)
	var lookup := _build_doc_lookup(doc_info, "methods")
	var result := []

	for m in raw:
		if not (m is Dictionary):
			continue
		var name := String(m.get("name", ""))
		if not _matches_filter(name, filter, lookup.get(name, {})):
			continue

		var entry := {
			"name": name,
			"return_type": _variant_type_str(
				int(m.get("return", {}).get("type", TYPE_NIL)),
				String(m.get("return", {}).get("class_name", "")),
			),
			"args": _doc_args(m.get("args", [])),
		}

		var dm = lookup.get(name)
		if dm != null:
			var desc := String(dm.get("description", ""))
			if not desc.is_empty():
				entry["description"] = desc

		result.append(entry)

	return result


func _doc_properties(cls_name: String, filter: String, no_inheritance: bool, doc_info) -> Array:
	var raw := ClassDB.class_get_property_list(cls_name, no_inheritance)
	var lookup := _build_doc_lookup(doc_info, "properties")
	var result := []

	for p in raw:
		if not (p is Dictionary):
			continue
		var name := String(p.get("name", ""))
		if not _matches_filter(name, filter, lookup.get(name, {})):
			continue

		var entry := {
			"name": name,
			"type": _variant_type_str(int(p.get("type", TYPE_NIL)), String(p.get("class_name", ""))),
		}

		var dp = lookup.get(name)
		if dp != null:
			var desc := String(dp.get("description", ""))
			if not desc.is_empty():
				entry["description"] = desc

		result.append(entry)

	return result


func _doc_signals(cls_name: String, filter: String, no_inheritance: bool, doc_info) -> Array:
	var raw := ClassDB.class_get_signal_list(cls_name, no_inheritance)
	var lookup := _build_doc_lookup(doc_info, "signals")
	var result := []

	for s in raw:
		if not (s is Dictionary):
			continue
		var name := String(s.get("name", ""))
		if not _matches_filter(name, filter, lookup.get(name, {})):
			continue

		var entry := {
			"name": name,
			"args": _doc_args(s.get("args", [])),
		}

		var ds = lookup.get(name)
		if ds != null:
			var desc := String(ds.get("description", ""))
			if not desc.is_empty():
				entry["description"] = desc

		result.append(entry)

	return result


func _doc_constants(cls_name: String, filter: String, no_inheritance: bool, doc_info) -> Array:
	var raw := ClassDB.class_get_integer_constant_list(cls_name, no_inheritance)
	var lookup := _build_doc_lookup(doc_info, "constants")
	var result := []

	for cname in raw:
		if not (cname is String):
			continue
		if not _matches_filter(cname, filter, lookup.get(cname, {})):
			continue

		var sname := String(cname)
		var entry := {
			"name": sname,
			"value": ClassDB.class_get_integer_constant(cls_name, sname),
		}
		var enum_name := ClassDB.class_get_integer_constant_enum(cls_name, sname)
		if not enum_name.is_empty():
			entry["enum"] = enum_name

		var dc = lookup.get(sname)
		if dc != null:
			var desc := String(dc.get("description", ""))
			if not desc.is_empty():
				entry["description"] = desc

		result.append(entry)

	return result


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


func _get_resource(arguments: Dictionary) -> Dictionary:
	var path := String(arguments.get("path", "")).strip_edges()
	if path.is_empty():
		return _tool_error("INVALID_PARAMS", "path is required")

	if not ResourceLoader.exists(path):
		return _tool_error("RESOURCE_NOT_FOUND", "Resource not found at path", {
			"path": path,
		})

	var resource = ResourceLoader.load(path)
	if resource == null:
		return _tool_error("LOAD_FAILED", "Failed to load resource, it may have unsupported type or invalid dependencies", {
			"path": path,
		})

	var max_depth := int(arguments.get("max_depth", 1))
	if max_depth < 0:
		max_depth = 0

	var result := _serialize_resource(resource, 0, max_depth)
	return _tool_success(result)


func _serialize_resource(resource: Resource, depth: int, max_depth: int) -> Dictionary:
	var result := {
		"type": resource.get_class(),
		"resource_path": resource.resource_path,
		"resource_name": resource.resource_name,
		"resource_local_to_scene": resource.resource_local_to_scene,
	}

	if depth >= max_depth:
		return result

	var properties := {}
	for prop in resource.get_property_list():
		var usage: int = int(prop.get("usage", 0))
		if usage & PROPERTY_USAGE_STORAGE == 0:
			continue

		var name := String(prop.get("name", ""))
		if name.is_empty():
			continue

		# Skip the built-in Resource meta-properties already surfaced above
		if name in ["resource_path", "resource_name", "resource_local_to_scene"]:
			continue

		properties[name] = _serialize_resource_value(resource.get(name), depth, max_depth)

	result["properties"] = properties
	return result


func _serialize_resource_value(value: Variant, depth: int, max_depth: int) -> Variant:
	match typeof(value):
		TYPE_NIL:
			return null
		TYPE_BOOL:
			return bool(value)
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return float(value)
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)

		TYPE_VECTOR2:
			var v: Vector2 = value
			return {"x": v.x, "y": v.y}
		TYPE_VECTOR2I:
			var v: Vector2i = value
			return {"x": v.x, "y": v.y}
		TYPE_VECTOR3:
			var v: Vector3 = value
			return {"x": v.x, "y": v.y, "z": v.z}
		TYPE_VECTOR3I:
			var v: Vector3i = value
			return {"x": v.x, "y": v.y, "z": v.z}
		TYPE_VECTOR4:
			var v: Vector4 = value
			return {"x": v.x, "y": v.y, "z": v.z, "w": v.w}
		TYPE_VECTOR4I:
			var v: Vector4i = value
			return {"x": v.x, "y": v.y, "z": v.z, "w": v.w}
		TYPE_QUATERNION:
			var q: Quaternion = value
			return {"x": q.x, "y": q.y, "z": q.z, "w": q.w}
		TYPE_RECT2:
			var r: Rect2 = value
			return {"position": {"x": r.position.x, "y": r.position.y}, "size": {"x": r.size.x, "y": r.size.y}}
		TYPE_RECT2I:
			var r: Rect2i = value
			return {"position": {"x": r.position.x, "y": r.position.y}, "size": {"x": r.size.x, "y": r.size.y}}
		TYPE_PLANE:
			var p: Plane = value
			return {"normal": {"x": p.normal.x, "y": p.normal.y, "z": p.normal.z}, "d": p.d}
		TYPE_COLOR:
			var c: Color = value
			return c.to_html(false)

		TYPE_ARRAY:
			var arr := []
			for item in value:
				arr.append(_serialize_resource_value(item, depth, max_depth))
			return arr

		TYPE_DICTIONARY:
			var dict := {}
			for key in value:
				dict[str(key)] = _serialize_resource_value(value[key], depth, max_depth)
			return dict

		TYPE_OBJECT:
			if value == null:
				return null
			if value is Resource:
				return _serialize_resource(value, depth + 1, max_depth)
			if value is Node:
				return {
					"type": value.get_class(),
					"name": value.name,
					"path": str(value.get_path()),
				}
			# Other engine objects (PhysicsBody, etc.) — return minimal info
			return {
				"type": value.get_class(),
				"id": value.get_instance_id(),
			}

		_:
			var str_value := str(value)
			if str_value.length() > 0:
				return str_value
			return null


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
