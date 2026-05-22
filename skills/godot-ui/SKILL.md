---
name: godot-ui
description: Build Godot Control UI layouts with containers, anchors, themes, UndoRedo, and complete MCP editor scripts.
license: MIT
compatibility: opencode, claude-code
metadata:
  project: GodotMCP
  workflow: ui
---

# Godot UI

Use this skill when creating or modifying `Control` nodes, containers, anchors, size flags, labels, buttons, panels, and simple themes.

## Tools

- Use `godot_get_editor_state` to confirm a scene is open.
- Use `godot_get_scene_snapshot` before targeting UI nodes.
- Use `godot_execute_editor_script` for all editor-side UI mutations.

## Critical Rules

- Send a complete GDScript editor script, not a snippet.
- The script must `extend RefCounted`.
- The script must define `func run(api: GodotMcpApi, args: Dictionary) -> Dictionary`.
- Return `api.success(...)` or `api.error(...)`.
- Use UndoRedo for every scene mutation.
- Set `owner` on newly added UI nodes that must be saved with the scene.
- Prefer containers (`MarginContainer`, `VBoxContainer`, `HBoxContainer`, `PanelContainer`) over manual offsets.
- Return only JSON-serializable values: strings, numbers, booleans, arrays, and dictionaries.

## Add A Centered Panel Layout

Use this to create a reusable UI block under the current scene root or a target `Control` parent.

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var scene := api.get_current_scene()
	if scene == null:
		return api.error("NO_SCENE", "No scene is currently open")

	var parent_path := NodePath(String(args.get("parent_path", "")))
	var parent: Node = scene
	if not String(parent_path).is_empty():
		parent = scene.get_node_or_null(parent_path)
		if parent == null:
			return api.error("NODE_NOT_FOUND", "No node found at path: " + String(parent_path))

	if not (parent is Control):
		return api.error("INVALID_PARENT", "Parent must be a Control node for this UI layout")

	var panel := PanelContainer.new()
	panel.name = String(args.get("name", "GeneratedPanel"))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(360, 180)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)

	var stack := VBoxContainer.new()
	stack.name = "Content"
	stack.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.name = "Title"
	title.text = String(args.get("title", "Generated UI"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var button := Button.new()
	button.name = "PrimaryButton"
	button.text = String(args.get("button_text", "Continue"))

	api.create_undo_action("Create UI Panel")
	api.add_do_method(parent, &"add_child", [panel])
	api.add_do_method(panel, &"set_owner", [scene])
	api.add_do_method(panel, &"add_child", [margin])
	api.add_do_method(margin, &"set_owner", [scene])
	api.add_do_method(margin, &"add_child", [stack])
	api.add_do_method(stack, &"set_owner", [scene])
	api.add_do_method(stack, &"add_child", [title])
	api.add_do_method(title, &"set_owner", [scene])
	api.add_do_method(stack, &"add_child", [button])
	api.add_do_method(button, &"set_owner", [scene])
	api.add_undo_method(parent, &"remove_child", [panel])
	api.commit_undo_action()

	return api.success({
		"created": panel.name,
		"parent": parent.name,
		"children": [margin.name, stack.name, title.name, button.name]
	})
```

## Update Control Text

Use UndoRedo for editing text on a label or button in the scene.

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var scene := api.get_current_scene()
	if scene == null:
		return api.error("NO_SCENE", "No scene is currently open")

	var node_path := NodePath(String(args.get("path", "")))
	var text := String(args.get("text", ""))
	if String(node_path).is_empty():
		return api.error("INVALID_ARGS", "Expected non-empty path")

	var node := scene.get_node_or_null(node_path)
	if node == null:
		return api.error("NODE_NOT_FOUND", "No node found at path: " + String(node_path))
	if not (node is Label or node is Button):
		return api.error("INVALID_NODE", "Node must be a Label or Button")

	var old_text: String = node.text
	api.create_undo_action("Update UI Text")
	api.add_do_property(node, &"text", text)
	api.add_undo_property(node, &"text", old_text)
	api.commit_undo_action()

	return api.success({"path": String(node_path), "old_text": old_text, "new_text": text})
```

## Validation Checklist

- Inspect the scene tree before targeting UI nodes.
- Prefer container hierarchy over manual positioning.
- Use UndoRedo for all node additions and property edits.
- Set `owner` for every newly added node that should save.
- Fetch a fresh scene snapshot after mutation.

## Common Mistakes

- Adding UI nodes without `owner`.
- Manually positioning every `Control` when containers are better.
- Editing text or layout without UndoRedo.
- Assuming the parent is a `Control`.
- Returning raw UI nodes from a script.
