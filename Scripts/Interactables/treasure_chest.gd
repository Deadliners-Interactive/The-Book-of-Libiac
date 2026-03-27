## Treasure chest interactable that opens when player touches it and spawns loot.
extends Node3D

# ==============================================================================
# Exports - Configuration
# ==============================================================================

@export var loot_scene: PackedScene
@export var spawn_offset: Vector3 = Vector3(0, 0.1, 0)
@export var open_duration: float = 0.5

# ==============================================================================
# Exports - Loot Settings
# ==============================================================================

@export var jump_distance: float = 0.05
@export var loot_scale: Vector3 = Vector3(2.0, 2.0, 2.0)

# ==============================================================================
# Member Variables
# ==============================================================================

var _is_open: bool = false
var _is_opening: bool = false

# ==============================================================================
# Onready Variables
# ==============================================================================

@onready var _tapa: Node3D = $tapa
@onready var _area: Area3D = $Area3D


# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	if not _tapa:
		push_error("Falta el nodo 'tapa'")
		return

	if not _area.area_entered.is_connected(_on_area_entered):
		_area.area_entered.connect(_on_area_entered)


# ==============================================================================
# Private Methods
# ==============================================================================

func _on_area_entered(area_hit: Area3D) -> void:
	if _is_open or _is_opening:
		return

	if not area_hit.is_in_group("hitbox_player"):
		return

	_open_chest()


func _open_chest() -> void:
	_is_opening = true

	_area.set_deferred("monitoring", false)
	_area.set_deferred("monitorable", false)

	# Animación de apertura de la tapa
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BOUNCE)

	var target_rotation_degrees: Vector3 = Vector3(24.6, 90.0, -90.0)
	tween.tween_property(_tapa, "rotation_degrees", target_rotation_degrees, open_duration)

	# Spawn del item a mitad de animación
	await get_tree().create_timer(open_duration * 0.3).timeout
	_spawn_loot()

	await tween.finished
	_is_open = true
	_is_opening = false


func _spawn_loot() -> void:
	if not loot_scene:
		return

	var item: Node = loot_scene.instantiate()

	item.scale = loot_scale

	add_child(item)

	var final_local_position: Vector3 = Vector3.ZERO

	final_local_position.y += spawn_offset.y

	final_local_position.z += jump_distance

	item.position = final_local_position
