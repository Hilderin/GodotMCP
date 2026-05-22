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
						"description": "Dictionary passed to run(api, args).",
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
			"description": "Return a compact snapshot of the Godot editor state.",
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
