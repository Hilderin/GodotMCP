extends RefCounted

const JsonRpc := preload("../utils/json_rpc.gd")

const PROTOCOL_VERSION := "2024-11-05"

var _tool_registry


func _init(tool_registry) -> void:
	_tool_registry = tool_registry


func parse_error(message: String) -> Dictionary:
	return JsonRpc.error(null, JsonRpc.PARSE_ERROR, message)


func handle(payload: Variant) -> Dictionary:
	if payload is Array:
		return _handle_batch(payload)

	var response: Variant = _handle_single(payload)
	return {
		"has_response": response != null,
		"response": response,
	}


func _handle_batch(payload: Array) -> Dictionary:
	if payload.is_empty():
		return {
			"has_response": true,
			"response": JsonRpc.error(null, JsonRpc.INVALID_REQUEST, "Invalid JSON-RPC batch"),
		}

	var responses: Array = []
	for item in payload:
		var response: Variant = _handle_single(item)
		if response != null:
			responses.append(response)

	return {
		"has_response": not responses.is_empty(),
		"response": responses,
	}


func _handle_single(request: Variant) -> Variant:
	if not (request is Dictionary):
		return JsonRpc.error(null, JsonRpc.INVALID_REQUEST, "Invalid JSON-RPC request")

	var id: Variant = request.get("id", null)
	var has_id: bool = request.has("id")

	if request.get("jsonrpc", "") != "2.0":
		return JsonRpc.error(id if has_id else null, JsonRpc.INVALID_REQUEST, "Invalid JSON-RPC version")

	if not request.has("method") or typeof(request["method"]) != TYPE_STRING:
		return JsonRpc.error(id if has_id else null, JsonRpc.INVALID_REQUEST, "Missing JSON-RPC method")

	if has_id and not JsonRpc.is_valid_id(id):
		return JsonRpc.error(null, JsonRpc.INVALID_REQUEST, "Invalid JSON-RPC id")

	var method: String = String(request["method"])
	var params: Variant = request.get("params", {})
	var result: Dictionary = _dispatch(method, params)

	if not has_id:
		return null

	if result.has("error"):
		return JsonRpc.error(id, int(result["error"].get("code", JsonRpc.INTERNAL_ERROR)), String(result["error"].get("message", "Internal error")), result["error"].get("data", null))

	return JsonRpc.result(id, result.get("result", {}))


func _dispatch(method: String, params: Variant) -> Dictionary:
	match method:
		"initialize":
			return {"result": _initialize_result(params)}
		"notifications/initialized":
			return {"result": {}}
		"ping":
			return {"result": {}}
		"tools/list":
			return {"result": {"tools": _tool_registry.list_tools()}}
		"tools/call":
			return _tool_call_not_implemented(params)
		_:
			return {"error": {"code": JsonRpc.METHOD_NOT_FOUND, "message": "Method not found: %s" % method}}


func _initialize_result(_params: Variant) -> Dictionary:
	return {
		"protocolVersion": PROTOCOL_VERSION,
		"capabilities": {
			"tools": {
				"listChanged": false,
			},
		},
		"serverInfo": {
			"name": "godot-mcp",
			"version": "0.1.0",
		},
	}


func _tool_call_not_implemented(params: Variant) -> Dictionary:
	var tool_name: String = ""
	if params is Dictionary:
		tool_name = String(params.get("name", ""))

	if tool_name.is_empty():
		return {"error": {"code": JsonRpc.INVALID_PARAMS, "message": "Missing tool name"}}

	if not _tool_registry.has_tool(tool_name):
		return {"error": {"code": JsonRpc.INVALID_PARAMS, "message": "Unknown tool: %s" % tool_name}}

	return {
		"error": {
			"code": JsonRpc.INTERNAL_ERROR,
			"message": "Tool execution is not implemented before later phases: %s" % tool_name,
		}
	}
