---
name: godot-scene-editing
description: Edit Godot scenes through Godot MCP tools using complete RefCounted editor scripts, UndoRedo, scene ownership, and serializable results.
license: MIT
compatibility: opencode, claude-code
metadata:
  project: GodotMCP
  workflow: scene-editing
---

# Godot Scene Editing

Use this skill when creating, deleting, renaming, reparenting, or changing nodes in the currently open Godot scene.

## Tools

- Use `godot_get_editor_state` before editing to confirm the editor and current scene state.
- Use `godot_get_scene_snapshot` to inspect the node tree before targeting nodes.
- Use `godot_execute_editor_script` for all editor-side scene mutations.

## Critical Rules

- Send a complete GDScript editor script, not a snippet.
- The script must `extend RefCounted`.
- The script must define `func run(api: GodotMcpApi, args: Dictionary) -> Dictionary`.
- Return `api.success(...)`, `api.error(...)`, or `api.warning(...)`.
- Use UndoRedo for every scene mutation.
- Set `owner` on newly added nodes that must be saved with the scene.
- Return only JSON-serializable values: strings, numbers, booleans, arrays, and dictionaries.
- Do not assume a scene is open. Check `api.get_current_scene()` first.
- Keep scripts short and targeted to one operation.

## Minimal Scene Check

Use this first when testing access or confirming that the skill/tool path works.

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var scene := api.get_current_scene()
	if scene == null:
		return api.error("NO_SCENE", "No scene is currently open")

	return api.success({
		"scene_name": scene.name,
		"scene_path": scene.scene_file_path,
		"child_count": scene.get_child_count()
	})
```

## Create A Node2D Child

Use UndoRedo and set `owner` so the new node is persisted when the scene is saved.

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var scene := api.get_current_scene()
	if scene == null:
		return api.error("NO_SCENE", "No scene is currently open")

	var node_name := String(args.get("name", "NewNode2D"))
	var child := Node2D.new()
	child.name = node_name

	api.create_undo_action("Create Node2D")
	api.add_do_method(scene, &"add_child", [child])
	api.add_do_method(child, &"set_owner", [scene])
	api.add_undo_method(scene, &"remove_child", [child])
	api.commit_undo_action()

	return api.success({
		"created": child.name,
		"parent": scene.name
	})
```

## Rename A Node

Resolve nodes from a known path in the current scene. Return clear errors when the target is missing.

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var scene := api.get_current_scene()
	if scene == null:
		return api.error("NO_SCENE", "No scene is currently open")

	var node_path := NodePath(String(args.get("path", "")))
	var new_name := String(args.get("name", ""))
	if String(node_path).is_empty() or new_name.is_empty():
		return api.error("INVALID_ARGS", "Expected non-empty path and name")

	var node := scene.get_node_or_null(node_path)
	if node == null:
		return api.error("NODE_NOT_FOUND", "No node found at path: " + String(node_path))

	var old_name := node.name
	api.create_undo_action("Rename Node")
	api.add_do_property(node, &"name", new_name)
	api.add_undo_property(node, &"name", old_name)
	api.commit_undo_action()

	return api.success({
		"path": String(node_path),
		"old_name": old_name,
		"new_name": new_name
	})
```

## Validation Checklist

- Inspect the scene before editing.
- Run one focused script per operation.
- Check the returned dictionary for `ok`, `error`, or warnings.
- Fetch a fresh scene snapshot after mutation.
- Save the scene only when the user asked for a persistent change.

## Common Mistakes

- Forgetting `extends RefCounted`.
- Returning a raw Godot `Object`, `Node`, or `Resource`.
- Creating nodes without `owner`, causing them not to save in the scene.
- Mutating the scene without UndoRedo.
- Guessing node paths instead of inspecting the scene tree first.
