extends RefCounted
class_name NotificationController

var cooldown_seconds: float = 1.0
var _notification_cooldown: Dictionary = {}


func can_emit(message: String) -> bool:
	var current_time: int = Time.get_ticks_msec()
	if _notification_cooldown.has(message):
		var last_shown_time: int = _notification_cooldown[message]
		if current_time - last_shown_time < int(cooldown_seconds * 1000):
			return false

	_notification_cooldown[message] = current_time
	return true
