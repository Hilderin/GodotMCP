# GodotMcpApi Reference

`GodotMcpApi` is passed to every `godot_execute_editor_script` script as the first argument of `run(api, args)`. Scripts should return a normalized result from `api.success(...)`, `api.error(...)`, or another dictionary with the same shape.

## Result Helpers

- `success(data: Dictionary = {}, meta: Dictionary = {}) -> Dictionary`
  - Returns a normalized successful tool result.
  - `data` and `meta` are converted to JSON-safe values.
  - Includes accumulated API warnings and logs.

- `error(code: String, message: String, details: Dictionary = {}) -> Dictionary`
  - Returns a normalized failed tool result.
  - Use stable `code` values such as `NO_SCENE`, `NODE_NOT_FOUND`, or `INVALID_ARGS`.
  - `details` is converted to JSON-safe values.

- `warning(message: String, details: Dictionary = {}) -> void`
  - Adds a warning to the eventual result.
  - Also records a warning log entry.

## Editor And Scene

- `get_editor_interface() -> EditorInterface`
  - Returns the active `EditorInterface`, or `null` if unavailable.
  - Use when a script needs Godot editor APIs not wrapped by this class.

- `get_current_scene() -> Node`
  - Returns `EditorInterface.get_edited_scene_root()`.
  - Returns `null` when no scene is currently open.

- `open_scene(path: String) -> Dictionary`
  - Opens a scene from a `res://` path and ensures it becomes the edited scene.
  - Selects and inspects the root node.
  - Switches the main editor screen to `3D` when the root is `Node3D`, or `2D` when the root is `CanvasItem`.
  - Returns `path`, `root_name`, `root_type`, and `main_screen` on success.

- `get_selection() -> Array[Node]`
  - Returns the current editor selection as an array of nodes.
  - Returns an empty array if the editor or selection is unavailable.

- `get_scene_tree_snapshot(root: Node = null, max_depth: int = 32, include_properties: bool = false, root_path: String = "", max_length: int = 0) -> Dictionary`
  - Returns a JSON-safe scene tree snapshot.
  - Defaults to the current edited scene when `root` is `null`.
  - `root_path` can target a sub-node relative to the scene root.
  - `max_length` enables best-effort truncation for very large scenes.

- `save_scene() -> Dictionary`
  - Saves the current edited scene through `EditorInterface.save_scene()`.
  - Fails if no scene is open or the scene has no file path.

## UndoRedo

- `get_undo_redo() -> EditorUndoRedoManager`
  - Returns `EditorInterface.get_editor_undo_redo()`, or `null` if unavailable.

- `create_undo_action(name: String) -> void`
  - Starts an editor UndoRedo action.
  - Use before scene mutations that should be undoable.

- `add_do_method(object: Object, method: StringName, args: Array = []) -> void`
  - Adds a do-method call to the active UndoRedo action.

- `add_undo_method(object: Object, method: StringName, args: Array = []) -> void`
  - Adds an undo-method call to the active UndoRedo action.

- `add_do_property(object: Object, property: StringName, value: Variant) -> void`
  - Adds a do-property change to the active UndoRedo action.

- `add_undo_property(object: Object, property: StringName, value: Variant) -> void`
  - Adds an undo-property change to the active UndoRedo action.

- `commit_undo_action() -> void`
  - Commits the active UndoRedo action.

- `cancel_undo_action() -> void`
  - Best-effort API-side cancellation marker.
  - Godot does not expose a public discard call for an active action.

## Resources And Paths

- `require_res_path(path: String) -> String`
  - Normalizes relative paths to `res://...`.
  - Allows existing `res://` and `user://` paths.
  - Rejects absolute filesystem paths by returning an empty string.

- `load_resource(path: String) -> Resource`
  - Loads a resource after normalizing the path with `require_res_path`.
  - Returns `null` and logs an error for invalid paths.

- `save_resource(resource: Resource, path: String = "") -> Dictionary`
  - Saves a resource to `path`, or to `resource.resource_path` when `path` is empty.
  - Rescans the editor filesystem after a successful save.

- `rescan_filesystem() -> void`
  - Calls `EditorFileSystem.scan()` when available.

## Logs

- `add_log(level: String, message: String, details: Dictionary = {}) -> void`
  - Adds a JSON-safe log entry to the API result metadata.

- `get_logs() -> Array`
  - Returns a duplicate of logs collected by this API instance.

## Script Pattern

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var opened := api.open_scene("res://levels/LevelPrototype.tscn")
	if not bool(opened.get("ok", false)):
		return opened

	var scene := api.get_current_scene()
	if scene == null:
		return api.error("NO_SCENE", "No scene is currently open")

	return api.success({
		"scene": scene.scene_file_path,
		"root": scene.name,
	})
```

## Notes

- Newly added nodes must have `owner` set to the scene root to be saved with the scene.
- Scene mutations should use the UndoRedo helpers unless the script is intentionally editing an off-tree resource or generated scene.
- Return only JSON-safe values. Do not return raw `Object`, `Node`, or `Resource` instances.
