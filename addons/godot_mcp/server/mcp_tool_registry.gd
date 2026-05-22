extends RefCounted


func list_tools() -> Array:
	return [
		{
			"name": "execute_editor_script",
			"description": "Execute a complete GDScript editor script inside Godot. Use this for scene editing, node creation, resource changes, project settings, input map, signals, UI layout, and other editor automation.",
			"inputSchema": {
				"type": "object",
				"properties": {
					"code": {
						"type": "string",
						"description": "Complete GDScript source. It must extend RefCounted and define run(api, args).",
					},
					"args": {
						"type": "object",
						"description": "Dictionary passed to run(api: GodotMcpApi, args: Dictionary).",
					},
					"timeout_ms": {
						"type": "integer",
						"description": "Optional execution timeout requested by the client.",
					},
				},
				"required": ["code"],
				"additionalProperties": false,
			},
		},
		{
			"name": "get_editor_state",
			"description": "Return a compact snapshot of the Godot editor state including godot version, editor path, project path, current scene, selection, and play status.",
			"inputSchema": _empty_object_schema(),
		},
		{
			"name": "get_scene_snapshot",
			"description": "Return the current scene tree hierarchy.",
			"inputSchema": {
				"type": "object",
				"properties": {
					"include_properties": {"type": "boolean"},
					"max_depth": {"type": "integer"},
					"path": {"type": "string"},
					"max_length": {"type": "integer"},
				},
				"additionalProperties": false,
			},
		},
		{
			"name": "get_logs",
			"description": "Return recent logs captured by the Godot MCP plugin.",
			"inputSchema": {
				"type": "object",
				"properties": {
					"source": {"type": "string"},
					"level": {"type": "string"},
					"limit": {"type": "integer"},
				},
				"additionalProperties": false,
			},
		},
		{
			"name": "run_project",
			"description": "Run the current Godot project or a specific scene.",
			"inputSchema": {
				"type": "object",
				"properties": {
					"scene_path": {"type": "string"},
				},
				"additionalProperties": false,
			},
		},
		{
			"name": "stop_project",
			"description": "Stop the currently running Godot project.",
			"inputSchema": _empty_object_schema(),
		},
		{
			"name": "capture_screenshot",
			"description": "Capture a screenshot of the Godot editor. Use this to let the AI agent visually inspect the editor state, viewport, or UI. Returns the image either as base64 (embedded in MCP response for direct AI analysis) or as a file path on disk.",
			"inputSchema": {
				"type": "object",
				"properties": {
					"return_mode": {
						"type": "string",
						"enum": ["base64", "path"],
						"description": "'base64' (default) embeds the image in the MCP response via standard ImageContent so the AI can see it directly. 'path' saves to a file and returns the path.",
						"default": "base64",
					},
					"area": {
						"type": "string",
						"enum": ["editor", "viewport"],
						"description": "'editor' (default) captures the full editor window. 'viewport' captures the 3D editor viewport (falls back to full editor if unavailable).",
						"default": "editor",
					},
					"output_dir": {
						"type": "string",
						"description": "Directory for the screenshot file (only used when return_mode is 'path'). Defaults to the system temporary directory.",
					},
				},
				"additionalProperties": false,
			},
		},
	]


func has_tool(name: String) -> bool:
	for tool in list_tools():
		if String(tool.get("name", "")) == name:
			return true
	return false


func _empty_object_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {},
		"additionalProperties": false,
	}
