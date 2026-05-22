extends RefCounted

const McpProtocol := preload("mcp_protocol.gd")
const McpToolRegistry := preload("mcp_tool_registry.gd")

const MAX_REQUEST_BYTES := 1048576

var log_callback: Callable = Callable()

var _server: TCPServer = TCPServer.new()
var _clients: Array = []
var _protocol
var _host: String = "127.0.0.1"
var _port: int = 9700


func _init(editor_interface: EditorInterface = null, log_buffer = null) -> void:
	_protocol = McpProtocol.new(McpToolRegistry.new(), editor_interface, log_buffer)


func start(host: String, port: int) -> Error:
	if _server.is_listening():
		stop()

	_host = host
	_port = port
	var error: Error = _server.listen(_port, _host)
	if error == OK:
		_log("MCP HTTP server listening on http://%s:%d" % [_host, _port])
	else:
		_log("failed to start MCP HTTP server on %s:%d (error %d)" % [_host, _port, error])
	return error


func stop() -> void:
	for client in _clients:
		var peer: StreamPeerTCP = client.get("peer") as StreamPeerTCP
		if peer != null:
			peer.disconnect_from_host()
	_clients.clear()

	if _server.is_listening():
		_server.stop()
		_log("MCP HTTP server stopped")


func is_running() -> bool:
	return _server.is_listening()


func poll() -> void:
	if not _server.is_listening():
		return

	while _server.is_connection_available():
		var peer: StreamPeerTCP = _server.take_connection()
		if peer != null:
			_clients.append({"peer": peer, "buffer": PackedByteArray()})

	for index in range(_clients.size() - 1, -1, -1):
		if _poll_client(_clients[index]):
			_clients.remove_at(index)


func _poll_client(client: Dictionary) -> bool:
	var peer: StreamPeerTCP = client.get("peer") as StreamPeerTCP
	if peer == null:
		return true

	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return true

	var available: int = peer.get_available_bytes()
	if available > 0:
		var read_result: Array = peer.get_data(available)
		if int(read_result[0]) != OK:
			_send_http_response(peer, 400, "Bad Request", "text/plain")
			return true

		var buffer: PackedByteArray = client["buffer"]
		var chunk: PackedByteArray = read_result[1]
		buffer.append_array(chunk)
		client["buffer"] = buffer

		if buffer.size() > MAX_REQUEST_BYTES:
			_send_http_response(peer, 413, "Request Entity Too Large", "text/plain")
			return true

	return _try_handle_request(client)


func _try_handle_request(client: Dictionary) -> bool:
	var peer: StreamPeerTCP = client["peer"] as StreamPeerTCP
	if peer == null:
		return true

	var buffer: PackedByteArray = client["buffer"]
	var request_text: String = buffer.get_string_from_utf8()
	var header_end: int = request_text.find("\r\n\r\n")
	if header_end == -1:
		return false

	var header_text: String = request_text.substr(0, header_end)
	var lines: PackedStringArray = header_text.split("\r\n")
	if lines.is_empty():
		_send_http_response(peer, 400, "Bad Request", "text/plain")
		return true

	var request_line: PackedStringArray = String(lines[0]).split(" ")
	if request_line.size() < 3:
		_send_http_response(peer, 400, "Bad Request", "text/plain")
		return true

	var method: String = String(request_line[0])
	var content_length: int = _parse_content_length(lines)
	var body_start: int = header_end + 4
	if buffer.size() < body_start + content_length:
		return false

	match method:
		"OPTIONS":
			_send_http_response(peer, 204, "", "text/plain")
		"GET":
			_send_json(peer, 200, {
				"name": "godot-mcp",
				"status": "ok",
				"transport": "streamable-http",
			})
		"POST":
			var body_bytes: PackedByteArray = buffer.slice(body_start, body_start + content_length)
			_handle_json_rpc(peer, body_bytes.get_string_from_utf8())
		_:
			_send_http_response(peer, 405, "Method Not Allowed", "text/plain")

	return true


func _handle_json_rpc(peer: StreamPeerTCP, body: String) -> void:
	var json: JSON = JSON.new()
	var parse_error: Error = json.parse(body)
	if parse_error != OK:
		_send_json(peer, 200, _protocol.parse_error(json.get_error_message()))
		return

	var protocol_response: Dictionary = _protocol.handle(json.data)
	if not bool(protocol_response.get("has_response", false)):
		_send_http_response(peer, 204, "", "application/json")
		return

	_send_json(peer, 200, protocol_response["response"])


func _parse_content_length(lines: PackedStringArray) -> int:
	for line in lines:
		var separator: int = String(line).find(":")
		if separator == -1:
			continue

		var key: String = String(line).substr(0, separator).strip_edges().to_lower()
		if key == "content-length":
			return max(0, String(line).substr(separator + 1).strip_edges().to_int())

	return 0


func _send_json(peer: StreamPeerTCP, status_code: int, payload: Variant) -> void:
	_send_http_response(peer, status_code, JSON.stringify(payload), "application/json")


func _send_http_response(peer: StreamPeerTCP, status_code: int, body: String, content_type: String) -> void:
	var body_bytes: PackedByteArray = body.to_utf8_buffer()
	var reason: String = _http_reason(status_code)
	var headers: String = "HTTP/1.1 %d %s\r\n" % [status_code, reason]
	headers += "Content-Type: %s; charset=utf-8\r\n" % content_type
	headers += "Content-Length: %d\r\n" % body_bytes.size()
	headers += "Connection: close\r\n"
	headers += "Access-Control-Allow-Origin: *\r\n"
	headers += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
	headers += "Access-Control-Allow-Headers: content-type, mcp-protocol-version\r\n"
	headers += "\r\n"

	var response_bytes: PackedByteArray = headers.to_utf8_buffer()
	response_bytes.append_array(body_bytes)
	peer.put_data(response_bytes)
	peer.disconnect_from_host()


func _http_reason(status_code: int) -> String:
	match status_code:
		200:
			return "OK"
		204:
			return "No Content"
		400:
			return "Bad Request"
		405:
			return "Method Not Allowed"
		413:
			return "Request Entity Too Large"
		_:
			return "HTTP Status"


func _log(message: String) -> void:
	if log_callback.is_valid():
		log_callback.call(message)
