---
name: godot-debugging
description: Diagnose Godot editor and runtime issues with MCP state, logs, run/stop loops, and complete read-only editor scripts.
license: MIT
compatibility: opencode, claude-code
metadata:
  project: GodotMCP
  workflow: debugging
---

# Godot Debugging

Use this skill when inspecting editor state, reading logs, running or stopping the project, reproducing errors, or gathering diagnostics before a small fix.

## Tools

- Use `godot_get_editor_state` before debugging to confirm project, scene, selection, and play state.
- Use `godot_get_scene_snapshot` to inspect the active scene without custom scripts.
- Use `godot_run_project` and `godot_stop_project` for runtime reproduction loops.
- Use `godot_get_logs` after running or stopping the project.
- Use `godot_execute_editor_script` for targeted editor diagnostics that the core tools do not expose.

## Critical Rules

- Send a complete GDScript editor script, not a snippet.
- The script must `extend RefCounted`.
- The script must define `func run(api: GodotMcpApi, args: Dictionary) -> Dictionary`.
- Return `api.success(...)` or `api.error(...)`.
- Use UndoRedo for every scene mutation. Debug scripts should usually be read-only.
- Return only JSON-serializable values: strings, numbers, booleans, arrays, and dictionaries.
- Reproduce the issue with the smallest useful run command before broad changes.
- Report GodotMCP failures with `error.code`, `error.message`, and useful `details`.

## Inspect Selection

Use this when a bug depends on the currently selected nodes.

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var scene := api.get_current_scene()
	if scene == null:
		return api.error("NO_SCENE", "No scene is currently open")

	var selected := []
	for node in api.get_selection():
		selected.append({
			"name": node.name,
			"type": node.get_class(),
			"path": str(scene.get_path_to(node)) if scene.is_ancestor_of(node) else str(node.get_path())
		})

	return api.success({
		"scene_name": scene.name,
		"scene_path": scene.scene_file_path,
		"selection": selected
	})
```

## Inspect Node Script

Use this to confirm whether a target node has a script and what script path it uses.

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

	var node_script: Variant = node.get_script()
	return api.success({
		"node": node.name,
		"type": node.get_class(),
		"script_path": node_script.resource_path if node_script is Resource else "",
		"has_process": node.has_method("_process"),
		"has_physics_process": node.has_method("_physics_process")
	})
```

## Validation Checklist

- Capture editor state before running the project.
- Run the project or target scene with the smallest reproduction path.
- Read recent logs, preferably filtered to `error` first.
- Inspect the scene or selected nodes only after confirming the current scene.
- Make one focused fix, then rerun and read logs again.

## Common Mistakes

- Guessing the current scene or selected node.
- Reading logs before reproducing the issue.
- Returning raw `Node`, `Resource`, or `Object` values.
- Making scene changes during diagnostics without UndoRedo.
- Continuing after a failed `execute_editor_script` without checking `error.code`.
