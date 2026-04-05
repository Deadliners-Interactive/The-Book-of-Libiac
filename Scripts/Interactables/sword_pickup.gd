## Sword pickup interactable.
## Registers the sword weapon for the player and removes itself when collected.
extends Node3D

# ==============================================================================
# Constants
# ==============================================================================

const WEAPON_ID: StringName = &"sword"


# ==============================================================================
# Onready Variables
# ==============================================================================

@onready var _area: Area3D = $Area3D


# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	if _area == null:
		push_error("SwordPickup: No se encontro Area3D")
		return

	_area.monitoring = true
	_area.monitorable = true
	if not _area.body_entered.is_connected(_on_body_entered):
		_area.body_entered.connect(_on_body_entered)


# ==============================================================================
# Private Methods
# ==============================================================================

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	if body.has_method("register_weapon"):
		body.register_weapon(WEAPON_ID)
		if body.has_method("show_notification"):
			body.show_notification("Espada obtenida")
		queue_free()
		return

	push_warning("SwordPickup: player no tiene register_weapon()")
