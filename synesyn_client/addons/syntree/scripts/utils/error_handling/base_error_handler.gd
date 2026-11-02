## Purpose: BaseErrorHandler (script)
# base_error_handler.gd
class_name BaseErrorHandler
extends Resource

var provider: String
var provider_error_patterns := {
	"Anthropic": {
		"context_limit": [
			"maximum context length",
			"too long",
			"reduce the length"
		],
		"rate_limit": [
			"rate limit",
			"too many requests"
		],
		"quota_exceeded": [
			"quota exceeded",
			"usage limit",
			"out of credits"
		]
	},
	"OpenAI": {
		"context_limit": [
			"maximum tokens",
			"context length",
			"content too long"
		],
		"rate_limit": [
			"rate limit exceeded",
			"requests per min"
		],
		"quota_exceeded": [
			"insufficient quota",
			"billing limit"
		]
	}
}

func _init(p_provider: String) -> void:
	provider = p_provider

func parse_error(code: int, body: String) -> Dictionary:
	print("DEBUG: Error Handler - Parsing error for provider: ", provider)
	print("DEBUG: Error Handler - Status code: ", code)
	print("DEBUG: Error Handler - Response body: ", body)
	
	var error_type = _determine_error_type(code, body)
	var error_messages = ErrorMessages.get_messages(error_type)
	var tech_details = _extract_technical_details(code, body)
	
	return {
		"type": error_type,
		"provider": provider,
		"message": error_messages.user_message,
		"solution": error_messages.solution,
		"raw_body": body,
		"details": tech_details
	}

func _extract_technical_details(code: int, body: String) -> Dictionary:
	var details = {
		"status_code": code
	}
	
	var json = JSON.parse_string(body)
	if json == null:
		return details
		
	if typeof(json) == TYPE_DICTIONARY:
		if json.has("error"):
			var error = json.error
			if typeof(error) == TYPE_DICTIONARY:
				if error.has("type"):
					details["error_type"] = error.type
				if error.has("code"):
					details["error_code"] = error.code
				if error.has("param"):
					details["parameter"] = error.param
	
	return details

func _determine_error_type(code: int, body: String) -> int:
	print("DEBUG: Error Handler - Analyzing error")
	print("DEBUG: Error Handler - Code: ", code)
	print("DEBUG: Error Handler - Body: ", body)
	print("DEBUG: Error Handler - Provider: ", provider)
	
	# Universal error codes
	match code:
		401:
			print("DEBUG: Error Handler - Matched 401 code, returning AUTH_ERROR")
			return ErrorMessages.ErrorType.AUTH_ERROR
		429:
			print("DEBUG: Error Handler - Matched 429 code, returning RATE_LIMIT")
			return ErrorMessages.ErrorType.RATE_LIMIT
		503:
			print("DEBUG: Error Handler - Matched 503 code, returning MODEL_UNAVAILABLE")
			return ErrorMessages.ErrorType.MODEL_UNAVAILABLE
	
	# Try to parse JSON response for structured errors
	var json = JSON.parse_string(body)
	if json and typeof(json) == TYPE_DICTIONARY and json.has("error"):
		var error_info = json.error
		print("DEBUG: Error Handler - Error info: ", error_info)
		
		# OpenAI-specific error codes
		if provider == "OpenAI" and error_info is Dictionary:
			var error_type = error_info.get("type", "")
			var error_code = error_info.get("code", "")
			print("DEBUG: Error Handler - OpenAI error type: ", error_type)
			print("DEBUG: Error Handler - OpenAI error code: ", error_code)
			
			match error_code:
				"invalid_api_key": 
					print("DEBUG: Error Handler - Matched invalid_api_key, returning AUTH_ERROR")
					return ErrorMessages.ErrorType.AUTH_ERROR
				"context_length_exceeded":
					return ErrorMessages.ErrorType.CONTEXT_LIMIT
				"rate_limit_exceeded":
					return ErrorMessages.ErrorType.RATE_LIMIT
				"insufficient_quota":
					return ErrorMessages.ErrorType.QUOTA_EXCEEDED
		
		# Anthropic-specific error codes
		elif provider == "Anthropic" and error_info is Dictionary:
			var error_type = error_info.get("type", "")
			print("DEBUG: Error Handler - Anthropic error type: ", error_type)
			
			match error_type:
				"authentication_error": 
					print("DEBUG: Error Handler - Matched authentication_error, returning AUTH_ERROR")
					return ErrorMessages.ErrorType.AUTH_ERROR
				"context_length_exceeded":
					return ErrorMessages.ErrorType.CONTEXT_LIMIT
				"rate_limit_error":
					return ErrorMessages.ErrorType.RATE_LIMIT
				"quota_exceeded":
					return ErrorMessages.ErrorType.QUOTA_EXCEEDED
	
	# If no specific match, check generic patterns
	var error_text = body.to_lower()
	if provider in provider_error_patterns:
		var patterns = provider_error_patterns[provider]
		
		for pattern in patterns.context_limit:
			if pattern in error_text:
				print("DEBUG: Error Handler - Matched context limit pattern: ", pattern)
				return ErrorMessages.ErrorType.CONTEXT_LIMIT
		
		for pattern in patterns.rate_limit:
			if pattern in error_text:
				print("DEBUG: Error Handler - Matched rate limit pattern: ", pattern)
				return ErrorMessages.ErrorType.RATE_LIMIT
		
		for pattern in patterns.quota_exceeded:
			if pattern in error_text:
				print("DEBUG: Error Handler - Matched quota exceeded pattern: ", pattern)
				return ErrorMessages.ErrorType.QUOTA_EXCEEDED
	
	print("DEBUG: Error Handler - No specific error type matched, returning UNKNOWN")
	return ErrorMessages.ErrorType.UNKNOWN
