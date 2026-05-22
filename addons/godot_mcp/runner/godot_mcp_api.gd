class_name GodotMcpApi
extends RefCounted


var _editor_interface = null
var _warnings: Array = []
var _logs: Array = []
var _undo_action_open: bool = false


func _init(editor_interface = null) -> void:
	_editor_interface = editor_interface
	if _editor_interface == null:
		_editor_interface = _get_editor_interface_singleton()


func success(data: Dictionary = {}, meta: Dictionary = {}) -> Dictionary:
	var normalized_meta := _meta_with_logs(meta)
	return {
		"ok": true,
		"data": _json_safe(data),
		"warnings": _warnings.duplicate(true),
		"meta": _json_safe(normalized_meta),
	}


func error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"error": {
			"code": code,
			"message": message,
			"details": _json_safe(details),
		},
		"warnings": _warnings.duplicate(true),
		"meta": _meta_with_logs({}),
	}


func warning(message: String, details: Dictionary = {}) -> void:
	_warnings.append({
		"message": message,
		"details": _json_safe(details),
	})
	add_log("warning", message, details)


func get_editor_interface():
	if _editor_interface == null:
		_editor_interface = _get_editor_interface_singleton()
	return _editor_interface


func get_current_scene() -> Node:
	var editor_interface = get_editor_interface()
	if editor_interface == null:
		return null
	return editor_interface.get_edited_scene_root()


func get_selection() -> Array[Node]:
	var nodes: Array[Node] = []
	var editor_interface = get_editor_interface()
	if editor_interface == null:
		return nodes

	var selection = editor_interface.get_selection()
	if selection == null:
		return nodes

	for node in selection.get_selected_nodes():
		if node is Node:
			nodes.append(node)
	return nodes


func get_scene_tree_snapshot(root: Node = null, max_depth: int = 32, include_properties: bool = false, root_path: String = "", max_length: int = 0) -> Dictionary:
	var target := root
	if target == null:
		target = get_current_scene()

	if target == null:
		return {
			"scene_path": "",
			"root": {},
		}

	if not root_path.is_empty():
		var resolved := _resolve_node_path(target, root_path)
		if resolved == null:
			return {
				"error": "Node not found: " + root_path,
			}
		target = resolved

	var depth_limit: int = clampi(max_depth, 0, 256)
	var budget: Array = [max_length] if max_length > 0 else []

	var result := {
		"scene_path": _node_scene_path(target),
		"root": _snapshot_node(target, 0, depth_limit, include_properties, target, budget),
	}

	if budget.size() > 0 and budget[0] <= 0:
		result["truncated"] = true

	return result


func get_undo_redo():
	var editor_interface = get_editor_interface()
	if editor_interface == null:
		return null
	return editor_interface.get_editor_undo_redo()


func create_undo_action(name: String) -> void:
	var undo_redo = get_undo_redo()
	if undo_redo == null:
		add_log("error", "UndoRedo is unavailable")
		return

	undo_redo.create_action(name)
	_undo_action_open = true


func add_do_method(object: Object, method: StringName, args: Array = []) -> void:
	var undo_redo = get_undo_redo()
	if undo_redo == null:
		add_log("error", "UndoRedo is unavailable")
		return

	var call_args: Array = [object, method]
	call_args.append_array(args)
	Callable(undo_redo, "add_do_method").callv(call_args)


func add_undo_method(object: Object, method: StringName, args: Array = []) -> void:
	var undo_redo = get_undo_redo()
	if undo_redo == null:
		add_log("error", "UndoRedo is unavailable")
		return

	var call_args: Array = [object, method]
	call_args.append_array(args)
	Callable(undo_redo, "add_undo_method").callv(call_args)


func add_do_property(object: Object, property: StringName, value: Variant) -> void:
	var undo_redo = get_undo_redo()
	if undo_redo == null:
		add_log("error", "UndoRedo is unavailable")
		return
	undo_redo.add_do_property(object, property, value)


func add_undo_property(object: Object, property: StringName, value: Variant) -> void:
	var undo_redo = get_undo_redo()
	if undo_redo == null:
		add_log("error", "UndoRedo is unavailable")
		return
	undo_redo.add_undo_property(object, property, value)


func commit_undo_action() -> void:
	var undo_redo = get_undo_redo()
	if undo_redo == null:
		add_log("error", "UndoRedo is unavailable")
		return

	undo_redo.commit_action()
	_undo_action_open = false


func cancel_undo_action() -> void:
	# Godot does not expose a public discard call; this helper only closes the API-side guard.
	_undo_action_open = false
	add_log("warning", "UndoRedo action cancellation is best-effort only")


func require_res_path(path: String) -> String:
	var normalized := path.strip_edges()
	if normalized.is_empty():
		return ""
	if normalized.begins_with("res://"):
		return normalized
	if normalized.begins_with("user://"):
		return normalized
	if normalized.is_absolute_path():
		return ""
	return "res://%s" % normalized.trim_prefix("/")


func load_resource(path: String) -> Resource:
	var resource_path := require_res_path(path)
	if resource_path.is_empty():
		add_log("error", "Invalid resource path", {"path": path})
		return null
	return ResourceLoader.load(resource_path)


func save_resource(resource: Resource, path: String = "") -> Dictionary:
	if resource == null:
		return error("INVALID_RESOURCE", "Resource must not be null")

	var target_path := path
	if target_path.is_empty():
		target_path = resource.resource_path
	target_path = require_res_path(target_path)
	if target_path.is_empty():
		return error("INVALID_RESOURCE_PATH", "Resource path must be inside res:// or user://", {"path": path})

	var save_error := ResourceSaver.save(resource, target_path)
	if save_error != OK:
		return error("RESOURCE_SAVE_ERROR", "Failed to save resource", {
			"path": target_path,
			"godot_error": int(save_error),
		})

	rescan_filesystem()
	return success({"path": target_path})


func rescan_filesystem() -> void:
	var editor_interface = get_editor_interface()
	if editor_interface == null:
		return

	var filesystem = editor_interface.get_resource_filesystem()
	if filesystem != null:
		filesystem.scan()


func add_log(level: String, message: String, details: Dictionary = {}) -> void:
	_logs.append({
		"level": level,
		"message": message,
		"details": _json_safe(details),
	})


func get_logs() -> Array:
	return _logs.duplicate(true)


func _meta_with_logs(meta: Dictionary) -> Dictionary:
	var normalized := meta.duplicate(true)
	if not _logs.is_empty() and not normalized.has("logs"):
		normalized["logs"] = get_logs()
	return normalized


func _get_editor_interface_singleton():
	if not Engine.has_singleton("EditorInterface"):
		return null
	return Engine.get_singleton("EditorInterface")


func _node_scene_path(node: Node) -> String:
	if node.scene_file_path != "":
		return node.scene_file_path

	var scene := get_current_scene()
	if scene != null:
		return scene.scene_file_path
	return ""


func _snapshot_node(node: Node, depth: int, max_depth: int, include_properties: bool, scene_root: Node, budget: Array = []) -> Dictionary:
	var snapshot := {
		"name": node.name,
		"type": node.get_class(),
		"path": _scene_node_path(node, scene_root),
		"scene_file_path": node.scene_file_path,
		"children": [],
	}

	if include_properties:
		snapshot["properties"] = _snapshot_properties(node)

	if budget.size() > 0:
		budget[0] -= _estimate_node_cost(snapshot)

	if depth >= max_depth:
		return snapshot

	for child in node.get_children():
		if child is Node:
			if budget.size() > 0 and budget[0] <= 0:
				snapshot["truncated"] = true
				break
			snapshot["children"].append(_snapshot_node(child, depth + 1, max_depth, include_properties, scene_root, budget))
	return snapshot


func _resolve_node_path(scene_root: Node, path: String) -> Node:
	var clean := path.trim_prefix("/")
	if clean.is_empty():
		return scene_root
	var parts := clean.split("/", true, 1)
	if parts.size() > 0 and parts[0] == scene_root.name:
		if parts.size() > 1 and not parts[1].is_empty():
			return scene_root.get_node_or_null(parts[1])
		return scene_root
	return scene_root.get_node_or_null(clean)


func _estimate_node_cost(snapshot: Dictionary) -> int:
	var cost := 0
	cost += str(snapshot.get("name", "")).length()
	cost += str(snapshot.get("type", "")).length()
	cost += str(snapshot.get("path", "")).length()
	cost += str(snapshot.get("scene_file_path", "")).length()
	cost += 80
	if snapshot.has("properties"):
		for key in snapshot["properties"]:
			cost += str(key).length() + 10
			var val := snapshot["properties"][key]
			cost += _estimate_value_cost(val)
	return cost


func _estimate_value_cost(value) -> int:
	match typeof(value):
		TYPE_NIL:
			return 4
		TYPE_BOOL:
			return 4 if value else 5
		TYPE_INT:
			return len(str(value))
		TYPE_FLOAT:
			return len("%.4f" % value)
		TYPE_STRING, TYPE_STRING_NAME:
			return len(str(value)) + 2
		TYPE_DICTIONARY:
			var total := 2
			for key in value:
				total += str(key).length() + 2
				total += _estimate_value_cost(value[key])
				total += 2
			return total
		TYPE_ARRAY:
			var total := 2
			for item in value:
				total += _estimate_value_cost(item)
				total += 1
			return total
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return 20
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return 30
		_:
			return str(value).length() + 2


func _scene_node_path(node: Node, scene_root: Node) -> String:
	if node == scene_root:
		return "/%s" % scene_root.name
	if scene_root.is_ancestor_of(node):
		return "/%s/%s" % [scene_root.name, str(scene_root.get_path_to(node))]
	return str(node.get_path())


func _snapshot_properties(object: Object) -> Dictionary:
	var properties := {}
	for property in object.get_property_list():
		var usage: int = int(property.get("usage", 0))
		if usage & PROPERTY_USAGE_STORAGE == 0:
			continue

		var name := String(property.get("name", ""))
		if name.is_empty():
			continue

		var value: Variant = object.get(name)
		var serialized: Variant = _json_safe(value)
		if serialized != null:
			properties[name] = serialized
	return properties


func _json_safe(value) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_VECTOR2:
			var vector2: Vector2 = value
			return {"x": vector2.x, "y": vector2.y}
		TYPE_VECTOR2I:
			var vector2i: Vector2i = value
			return {"x": vector2i.x, "y": vector2i.y}
		TYPE_VECTOR3:
			var vector3: Vector3 = value
			return {"x": vector3.x, "y": vector3.y, "z": vector3.z}
		TYPE_VECTOR3I:
			var vector3i: Vector3i = value
			return {"x": vector3i.x, "y": vector3i.y, "z": vector3i.z}
		TYPE_VECTOR4:
			var vector4: Vector4 = value
			return {"x": vector4.x, "y": vector4.y, "z": vector4.z, "w": vector4.w}
		TYPE_VECTOR4I:
			var vector4i: Vector4i = value
			return {"x": vector4i.x, "y": vector4i.y, "z": vector4i.z, "w": vector4i.w}
		TYPE_QUATERNION:
			var quaternion: Quaternion = value
			return {"x": quaternion.x, "y": quaternion.y, "z": quaternion.z, "w": quaternion.w}
		TYPE_RECT2:
			var rect2: Rect2 = value
			return {
				"position": _json_safe(rect2.position),
				"size": _json_safe(rect2.size),
			}
		TYPE_RECT2I:
			var rect2i: Rect2i = value
			return {
				"position": _json_safe(rect2i.position),
				"size": _json_safe(rect2i.size),
			}
		TYPE_COLOR:
			var color: Color = value
			return color.to_html()
		TYPE_ARRAY:
			var array := []
			for item in value:
				var serialized_item: Variant = _json_safe(item)
				if serialized_item != null:
					array.append(serialized_item)
			return array
		TYPE_DICTIONARY:
			var dictionary := {}
			for key in value.keys():
				var serialized_key := str(key)
				var serialized_value: Variant = _json_safe(value[key])
				if serialized_value != null:
					dictionary[serialized_key] = serialized_value
			return dictionary
		TYPE_OBJECT:
			if value is Resource:
				return {
					"type": value.get_class(),
					"path": value.resource_path,
				}
			if value is Node:
				return {
					"type": value.get_class(),
					"path": str(value.get_path()),
					"name": value.name,
				}
			return null
		_:
			return null
