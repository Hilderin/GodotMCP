---
name: godot-resources
description: Load, create, assign, save, and rescan Godot resources through complete MCP editor scripts.
license: MIT
compatibility: opencode, claude-code
metadata:
  project: GodotMCP
  workflow: resources
---

# Godot Resources

Use this skill when loading resources, creating resources, assigning resources to nodes, saving resources, or rescanning the filesystem.

## Tools

- Use `godot_get_editor_state` to confirm the active project and scene.
- Use `godot_get_scene_snapshot` before assigning resources to scene nodes.
- Use `godot_execute_editor_script` for resource loading, saving, assignment, and filesystem rescans.

## Critical Rules

- Send a complete GDScript editor script, not a snippet.
- The script must `extend RefCounted`.
- The script must define `func run(api: GodotMcpApi, args: Dictionary) -> Dictionary`.
- Return `api.success(...)` or `api.error(...)`.
- Use `api.require_res_path(...)` for user-provided paths.
- Use UndoRedo for every scene mutation, including assigning a resource to a node property.
- Return only JSON-serializable values: strings, numbers, booleans, arrays, and dictionaries.
- Do not write outside `res://` or `user://`.

## Load A Resource

Use this to verify that a path resolves and the resource can be loaded.

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var path := api.require_res_path(String(args.get("path", "")))
	if path.is_empty():
		return api.error("INVALID_RESOURCE_PATH", "Expected a resource path inside res:// or user://")

	var resource := ResourceLoader.load(path)
	if resource == null:
		return api.error("RESOURCE_NOT_FOUND", "Could not load resource", {"path": path})

	return api.success({
		"path": path,
		"type": resource.get_class(),
		"resource_name": resource.resource_name
	})
```

## Create And Save A StandardMaterial3D

Use this when generating a small reusable resource file.

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var path := api.require_res_path(String(args.get("path", "materials/new_material.tres")))
	if path.is_empty():
		return api.error("INVALID_RESOURCE_PATH", "Expected a resource path inside res:// or user://")

	var material := StandardMaterial3D.new()
	material.resource_name = String(args.get("name", "NewMaterial"))
	material.albedo_color = Color.html(String(args.get("color", "#ffffff")))

	var result := api.save_resource(material, path)
	if not result.get("ok", false):
		return result

	return api.success({
		"path": path,
		"type": material.get_class(),
		"resource_name": material.resource_name
	})
```

## Assign Resource To Node Property

Use UndoRedo because this mutates the current scene.

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var scene := api.get_current_scene()
	if scene == null:
		return api.error("NO_SCENE", "No scene is currently open")

	var node_path := NodePath(String(args.get("node_path", "")))
	var property_name := StringName(String(args.get("property", "")))
	var resource_path := api.require_res_path(String(args.get("resource_path", "")))
	if String(node_path).is_empty() or String(property_name).is_empty() or resource_path.is_empty():
		return api.error("INVALID_ARGS", "Expected node_path, property, and resource_path")

	var node := scene.get_node_or_null(node_path)
	if node == null:
		return api.error("NODE_NOT_FOUND", "No node found at path: " + String(node_path))

	var resource := ResourceLoader.load(resource_path)
	if resource == null:
		return api.error("RESOURCE_NOT_FOUND", "Could not load resource", {"path": resource_path})

	var old_value: Variant = node.get(property_name)
	api.create_undo_action("Assign Resource")
	api.add_do_property(node, property_name, resource)
	api.add_undo_property(node, property_name, old_value)
	api.commit_undo_action()

	return api.success({
		"node_path": String(node_path),
		"property": String(property_name),
		"resource_path": resource_path
	})
```

## Validation Checklist

- Normalize paths with `api.require_res_path`.
- Verify loads before assigning resources.
- Use UndoRedo for assignments to scene nodes.
- Call `api.save_resource` for generated resources.
- Return resource paths and types, not resource objects.

## Common Mistakes

- Saving to an absolute path or outside the project.
- Returning a raw `Resource`.
- Assigning a resource to a node without UndoRedo.
- Forgetting to rescan after saving files manually.
- Assuming a node property accepts the loaded resource type.
