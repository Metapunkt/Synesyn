extends Popup

signal new_thread_requested
signal summarize_requested
signal end_session_requested

func _ready():
	#$NewThreadButton.connect("pressed", self, "_on_new_thread_pressed")
	#$SummarizeButton.connect("pressed", self, "_on_summarize_pressed")
	#$EndSessionButton.connect("pressed", self, "_on_end_session_pressed")
	
	$NewThreadButton.pressed.connect(_on_new_thread_pressed)
	$SummarizeButton.pressed.connect(_on_summarize_pressed)
	$EndSessionButton.pressed.connect(_on_end_session_pressed)

func _on_new_thread_pressed():
	emit_signal("new_thread_requested")
	hide()

func _on_summarize_pressed():
	emit_signal("summarize_requested")
	hide()

func _on_end_session_pressed():
	emit_signal("end_session_requested")
	hide()
