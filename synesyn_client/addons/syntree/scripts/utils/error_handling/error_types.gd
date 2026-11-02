## Purpose: AIError (script)
# error_types.gd
class_name AIError
extends Resource

enum ErrorType {
	CONTEXT_LIMIT,
	AUTH_ERROR,
	RATE_LIMIT,
	QUOTA_EXCEEDED,
	NETWORK_ERROR,
	MODEL_UNAVAILABLE,
	INVALID_INPUT,
	UNKNOWN
}

var error_type: ErrorType
var provider: String
var raw_code: String
var raw_message: String
var user_message: String
var solution: String

func _init(p_type: ErrorType, p_provider: String, p_code: String, p_message: String) -> void:
	error_type = p_type
	provider = p_provider
	raw_code = p_code
	raw_message = p_message
	_set_messages()

func _set_messages() -> void:
	var messages = ErrorMessages.get_messages(error_type)
	user_message = messages.user_message
	solution = messages.solution
