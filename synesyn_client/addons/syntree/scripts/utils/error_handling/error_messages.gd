## Purpose: ErrorMessages (script)
# error_messages.gd
class_name ErrorMessages

enum ErrorType {
	UNKNOWN,
	AUTH_ERROR,
	RATE_LIMIT,
	CONTEXT_LIMIT,
	QUOTA_EXCEEDED,
	MODEL_UNAVAILABLE
}

static func get_messages(error_type: int) -> Dictionary:
	match error_type:
		ErrorType.CONTEXT_LIMIT:
			return {
				"user_message": "This conversation has exceeded the AI's memory limit",
				"solution": "Please create a new chat thread to continue. This helps the AI maintain focus on your current topic."
			}
		ErrorType.AUTH_ERROR:
			return {
				"user_message": "There's a problem with the API authentication",
				"solution": "Please check your API key in the settings and ensure it's valid"
			}
		ErrorType.RATE_LIMIT:
			return {
				"user_message": "Too many requests in a short time",
				"solution": "Please wait a moment before sending another message"
			}
		ErrorType.QUOTA_EXCEEDED:
			return {
				"user_message": "You've reached your API usage limit",
				"solution": "Please check your API account credits or billing status"
			}
		ErrorType.MODEL_UNAVAILABLE:
			return {
				"user_message": "The AI model is temporarily unavailable",
				"solution": "Please try again in a few minutes or switch to a different model"
			}
		_:
			return {
				"user_message": "An unexpected error occurred",
				"solution": "Please try again or contact support if the problem persists"
			}
