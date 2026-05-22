extends RefCounted

const PARSE_ERROR := -32700
const INVALID_REQUEST := -32600
const METHOD_NOT_FOUND := -32601
const INVALID_PARAMS := -32602
const INTERNAL_ERROR := -32603


static func result(id: Variant, value: Variant) -> Dictionary:
	return {
		"jsonrpc": "2.0",
		"id": normalize_id(id),
		"result": value,
	}


static func error(id: Variant, code: int, message: String, data: Variant = null) -> Dictionary:
	var payload: Dictionary = {
		"jsonrpc": "2.0",
		"id": normalize_id(id),
		"error": {
			"code": code,
			"message": message,
		},
	}

	if data != null:
		payload["error"]["data"] = data

	return payload


static func is_valid_id(id: Variant) -> bool:
	var type: int = typeof(id)
	return type == TYPE_NIL or type == TYPE_INT or type == TYPE_FLOAT or type == TYPE_STRING


static func normalize_id(id: Variant) -> Variant:
	if typeof(id) == TYPE_FLOAT and is_equal_approx(id, round(id)):
		return int(id)
	return id
