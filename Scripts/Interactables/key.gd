## Key interactable item that gives player a key when picked up.
extends Node3D

# ==============================================================================
# Onready Variables
# ==============================================================================

@onready var _area: Area3D = $Area3D


# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	_area.monitoring = true
	_area.monitorable = true
	if not _area.body_entered.is_connected(_on_body_entered):
		_area.body_entered.connect(_on_body_entered)


# ==============================================================================
# Private Methods - Signal Handlers
# ==============================================================================

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	if body.has_method("add_key"):
		body.add_key()
		queue_free()
	else:
		push_warning("Key: player no tiene add_key()")
