---
name: godot-signals
description: Inspect, connect, and disconnect Godot signals safely with complete MCP editor scripts and UndoRedo.
license: MIT
compatibility: opencode, claude-code
metadata:
  project: GodotMCP
  workflow: signals
---

# Godot Signals

Use this skill when listing signals, connecting signals to methods, disconnecting signals, or checking existing signal connections.

## Tools

- Use `godot_get_editor_state` before editing signals.
- Use `godot_get_scene_snapshot` to confirm node paths.
- Use `godot_execute_editor_script` for signal inspection and connection changes.

## Critical Rules

- Send a complete GDScript editor script, not a snippet.
- The script must `extend RefCounted`.
- The script must define `func run(api: GodotMcpApi, args: Dictionary) -> Dictionary`.
- Return `api.success(...)` or `api.error(...)`.
- Use UndoRedo for every scene mutation, including persistent signal connection changes.
- Check for existing connections before connecting to avoid duplicates.
- Return only JSON-serializable values: strings, numbers, booleans, arrays, and dictionaries.
- Do not assume node paths or callback method names. Validate them first.

## List Node Signals

Use this to inspect available signal names and arguments.

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var scene := api.get_current_scene()
	if scene == null:
		return api.error("NO_SCENE", "No scene is currently open")

	var node_path := NodePath(String(args.get("path", "")))
	if String(node_path).is_empty():
		return api.error("INVALID_ARGS", "Expected non-empty path")

	var node := scene.get_node_or_null(node_path)
	if node == null:
		return api.error("NODE_NOT_FOUND", "No node found at path: " + String(node_path))

	var signals := []
	for signal_info in node.get_signal_list():
		var args_list := []
		for argument in signal_info.get("args", []):
			args_list.append({
				"name": String(argument.get("name", "")),
				"type": int(argument.get("type", TYPE_NIL))
			})
		signals.append({
			"name": String(signal_info.get("name", "")),
			"args": args_list
		})

	return api.success({"path": String(node_path), "signals": signals})
```

## Connect Signal To Method

Use UndoRedo and `Object.CONNECT_PERSIST` so the connection is saved with the scene.

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var scene := api.get_current_scene()
	if scene == null:
		return api.error("NO_SCENE", "No scene is currently open")

	var emitter_path := NodePath(String(args.get("emitter_path", "")))
	var target_path := NodePath(String(args.get("target_path", "")))
	var signal_name := StringName(String(args.get("signal", "")))
	var method_name := StringName(String(args.get("method", "")))
	if String(emitter_path).is_empty() or String(target_path).is_empty() or String(signal_name).is_empty() or String(method_name).is_empty():
		return api.error("INVALID_ARGS", "Expected emitter_path, target_path, signal, and method")

	var emitter := scene.get_node_or_null(emitter_path)
	var target := scene.get_node_or_null(target_path)
	if emitter == null:
		return api.error("NODE_NOT_FOUND", "Emitter not found", {"path": String(emitter_path)})
	if target == null:
		return api.error("NODE_NOT_FOUND", "Target not found", {"path": String(target_path)})
	if not target.has_method(method_name):
		return api.error("METHOD_NOT_FOUND", "Target does not define callback method", {"method": String(method_name)})

	var callable := Callable(target, method_name)
	if emitter.is_connected(signal_name, callable):
		return api.success({
			"connected": false,
			"reason": "already_connected",
			"emitter_path": String(emitter_path),
			"target_path": String(target_path),
			"signal": String(signal_name),
			"method": String(method_name)
		})

	api.create_undo_action("Connect Signal")
	api.add_do_method(emitter, &"connect", [signal_name, callable, int(Object.CONNECT_PERSIST)])
	api.add_undo_method(emitter, &"disconnect", [signal_name, callable])
	api.commit_undo_action()

	return api.success({
		"connected": true,
		"emitter_path": String(emitter_path),
		"target_path": String(target_path),
		"signal": String(signal_name),
		"method": String(method_name)
	})
```

## Disconnect Signal

Use this when removing a known connection. Reconnect on undo with `CONNECT_PERSIST`.

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var scene := api.get_current_scene()
	if scene == null:
		return api.error("NO_SCENE", "No scene is currently open")

	var emitter_path := NodePath(String(args.get("emitter_path", "")))
	var target_path := NodePath(String(args.get("target_path", "")))
	var signal_name := StringName(String(args.get("signal", "")))
	var method_name := StringName(String(args.get("method", "")))
	if String(emitter_path).is_empty() or String(target_path).is_empty() or String(signal_name).is_empty() or String(method_name).is_empty():
		return api.error("INVALID_ARGS", "Expected emitter_path, target_path, signal, and method")

	var emitter := scene.get_node_or_null(emitter_path)
	var target := scene.get_node_or_null(target_path)
	if emitter == null or target == null:
		return api.error("NODE_NOT_FOUND", "Emitter or target not found")

	var callable := Callable(target, method_name)
	if not emitter.is_connected(signal_name, callable):
		return api.success({"disconnected": false, "reason": "not_connected"})

	api.create_undo_action("Disconnect Signal")
	api.add_do_method(emitter, &"disconnect", [signal_name, callable])
	api.add_undo_method(emitter, &"connect", [signal_name, callable, int(Object.CONNECT_PERSIST)])
	api.commit_undo_action()

	return api.success({
		"disconnected": true,
		"emitter_path": String(emitter_path),
		"target_path": String(target_path),
		"signal": String(signal_name),
		"method": String(method_name)
	})
```

## Validation Checklist

- Inspect scene paths before connecting.
- Confirm the target method exists.
- Check `is_connected` before adding a connection.
- Use UndoRedo for persistent connection changes.
- Fetch a fresh scene snapshot or re-run diagnostics after mutation.

## Common Mistakes

- Connecting duplicate signals.
- Connecting to a missing callback method.
- Forgetting `Object.CONNECT_PERSIST` for scene-saved connections.
- Changing connections without UndoRedo.
- Returning raw `Callable`, `Signal`, or `Node` values.
