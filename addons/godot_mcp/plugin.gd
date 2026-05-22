@tool
extends EditorPlugin

const McpHttpServer := preload("server/mcp_http_server.gd")

const SETTING_ENABLED := "godot_mcp/enabled"
const SETTING_HTTP_HOST := "godot_mcp/http_host"
const SETTING_HTTP_PORT := "godot_mcp/http_port"

const DEFAULT_ENABLED := true
const DEFAULT_HTTP_HOST := "127.0.0.1"
const DEFAULT_HTTP_PORT := 9700

var _active: bool = false
var _server = null


func _enter_tree() -> void:
	_register_project_settings()

	if bool(ProjectSettings.get_setting(SETTING_ENABLED)):
		_active = true
		var host: String = String(ProjectSettings.get_setting(SETTING_HTTP_HOST))
		var port: int = int(ProjectSettings.get_setting(SETTING_HTTP_PORT))
		_start_server(host, port)
	else:
		_log("plugin loaded but disabled by %s" % SETTING_ENABLED)


func _exit_tree() -> void:
	_stop_server()
	if _active:
		_log("plugin unloaded")
	_active = false
	set_process(false)


func _process(_delta: float) -> void:
	if _server != null:
		_server.poll()


func _register_project_settings() -> void:
	_ensure_setting(SETTING_ENABLED, TYPE_BOOL, DEFAULT_ENABLED)
	_ensure_setting(SETTING_HTTP_HOST, TYPE_STRING, DEFAULT_HTTP_HOST)
	_ensure_setting(SETTING_HTTP_PORT, TYPE_INT, DEFAULT_HTTP_PORT, PROPERTY_HINT_RANGE, "1,65535,1")


func _ensure_setting(name: String, type: int, default_value: Variant, hint: int = PROPERTY_HINT_NONE, hint_string: String = "") -> void:
	if not ProjectSettings.has_setting(name):
		ProjectSettings.set_setting(name, default_value)

	var property_info: Dictionary = {
		"name": name,
		"type": type,
		"hint": hint,
		"hint_string": hint_string,
	}
	ProjectSettings.add_property_info(property_info)


func _start_server(host: String, port: int) -> void:
	_server = McpHttpServer.new(get_editor_interface())
	_server.log_callback = Callable(self, "_log")
	var error: Error = _server.start(host, port)
	if error != OK:
		_active = false
		return

	set_process(true)


func _stop_server() -> void:
	if _server != null:
		_server.stop()
		_server = null


func _log(message: String) -> void:
	print("[GodotMCP] %s" % message)
