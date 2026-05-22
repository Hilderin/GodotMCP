---
name: godot-input-project-settings
description: Edit Godot InputMap, project settings, and lightweight autoload settings with complete MCP editor scripts.
license: MIT
compatibility: opencode, claude-code
metadata:
  project: GodotMCP
  workflow: input-project-settings
---

# Godot Input And Project Settings

Use this skill when reading or changing `InputMap`, `ProjectSettings`, autoload entries, or other project-wide configuration.

## Tools

- Use `godot_get_editor_state` before changing project-wide settings.
- Use `godot_execute_editor_script` for `InputMap` and `ProjectSettings` operations.
- Use `godot_get_logs` if `ProjectSettings.save()` or runtime verification fails.

## Critical Rules

- Send a complete GDScript editor script, not a snippet.
- The script must `extend RefCounted`.
- The script must define `func run(api: GodotMcpApi, args: Dictionary) -> Dictionary`.
- Return `api.success(...)` or `api.error(...)`.
- Use UndoRedo for every scene mutation. Project settings are not scene mutations, but they should be saved deliberately.
- Return only JSON-serializable values: strings, numbers, booleans, arrays, and dictionaries.
- Call `ProjectSettings.save()` only when the task requires persistence.
- Warn that some project settings require a reload or editor restart.

## Add Input Action With Keycode

Use this for a simple keyboard action. Pass `keycode` as an integer Godot keycode.

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var action := StringName(String(args.get("action", "")))
	var keycode := int(args.get("keycode", 0))
	if String(action).is_empty() or keycode == 0:
		return api.error("INVALID_ARGS", "Expected action and non-zero keycode")

	var created := false
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		created = true

	var event := InputEventKey.new()
	event.keycode = keycode
	var already_exists := false
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.keycode == keycode:
			already_exists = true
			break

	if not already_exists:
		InputMap.action_add_event(action, event)

	var save_error := ProjectSettings.save()
	if save_error != OK:
		return api.error("PROJECT_SETTINGS_SAVE_ERROR", "Failed to save project settings", {"godot_error": int(save_error)})

	return api.success({
		"action": String(action),
		"created": created,
		"event_added": not already_exists,
		"keycode": keycode
	})
```

## Set Project Setting

Use this for scalar settings that can be represented in JSON.

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var key := String(args.get("key", ""))
	if key.is_empty():
		return api.error("INVALID_ARGS", "Expected non-empty key")

	if not args.has("value"):
		return api.error("INVALID_ARGS", "Expected value")

	var old_value: Variant = ProjectSettings.get_setting(key, null)
	ProjectSettings.set_setting(key, args["value"])
	var save_error := ProjectSettings.save()
	if save_error != OK:
		ProjectSettings.set_setting(key, old_value)
		return api.error("PROJECT_SETTINGS_SAVE_ERROR", "Failed to save project settings", {"godot_error": int(save_error)})

	api.warning("Some project settings require an editor reload or project restart")
	return api.success({
		"key": key,
		"old_value": old_value,
		"new_value": args["value"]
	})
```

## Add Autoload Setting

Use this only after confirming the script path exists.

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var name := String(args.get("name", ""))
	var path := api.require_res_path(String(args.get("path", "")))
	if name.is_empty() or path.is_empty():
		return api.error("INVALID_ARGS", "Expected name and path")

	if not ResourceLoader.exists(path):
		return api.error("RESOURCE_NOT_FOUND", "Autoload script does not exist", {"path": path})

	var key := "autoload/%s" % name
	ProjectSettings.set_setting(key, "*" + path)
	var save_error := ProjectSettings.save()
	if save_error != OK:
		return api.error("PROJECT_SETTINGS_SAVE_ERROR", "Failed to save project settings", {"godot_error": int(save_error)})

	api.warning("Autoload changes usually require a project reload")
	return api.success({"name": name, "path": path, "setting": key})
```

## Validation Checklist

- Confirm the project state before editing global settings.
- Use explicit, non-empty action names and setting keys.
- Avoid duplicate `InputMap` events.
- Save settings only when persistence is intended.
- Reopen or rerun the project when a setting requires reload.

## Common Mistakes

- Treating project settings changes as undoable scene edits.
- Forgetting that InputMap runtime changes are not enough without `ProjectSettings.save()`.
- Adding duplicate input events.
- Using absolute paths for autoload scripts.
- Assuming all settings apply immediately.
