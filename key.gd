# Key.gd
extends Node3D

@onready var area: Area3D = $Area3D

func _ready():
	# asegurar que el Area3D monitorice
	area.monitoring = true
	area.monitorable = true
	if not area.body_entered.is_connected(_on_body_entered):
		area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node):
	# solo jugadores
	if not body.is_in_group("player"):
		return

	# llamar método add_key si existe
	if body.has_method("add_key"):
		body.add_key()
		print("Key: recogida por ", body.name)
		queue_free()
	else:
		push_warning("Key: player no tiene add_key()")
