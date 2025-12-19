# HealthPickup.gd - Item que cura HP
extends Node3D

@export var heal_amount: float = 10.0
@export var enable_rotation: bool = true 
@export var rotation_speed: float = 2.0
@export var bob_speed: float = 2.0
@export var bob_height: float = 0.3
@export var use_billboard: bool = false

var time_passed: float = 0.0
var start_y: float = 0.0
var collected: bool = false

@onready var sprite: Sprite3D = $Sprite3D
@onready var area: Area3D = $Area3D

func _ready():
	print("Inicializando item de curación...")
	
	start_y = global_position.y
	
	if sprite and use_billboard:
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.pixel_size = 0.01
	
	if area:
		area.monitoring = true
		area.monitorable = true
		
		if not area.body_entered.is_connected(_on_body_entered):
			area.body_entered.connect(_on_body_entered)
	else:
		push_error("No se encontró Area3D!")
		return
	
	print("Listo para ser recogido")

func _process(delta):
	if collected:
		return
	
	time_passed += delta
	
	if enable_rotation:
		rotate_y(rotation_speed * delta)
	
	# flotación arriba y abajo
	var new_y = start_y + sin(time_passed * bob_speed) * bob_height
	global_position.y = new_y

func _on_body_entered(body: Node):
	if collected:
		return
	
	if not body.is_in_group("player"):
		return
	
	if not body.has_method("heal"):
		push_warning("❤️ HealthPickup: El player no tiene el método heal()")
		return
	
	if body.current_health >= body.max_health:
		print("❤️ HealthPickup: El player ya tiene vida completa")
		
		if body.has_method("show_notification"):
			body.show_notification("¡Ya tienes la vida completa!")
		return
		
	# Aplicar la curación
	collected = true
	body.heal(heal_amount)
	
	print("¡Recogido! +%.1f HP curados" % heal_amount)
	
	# Efecto de recogida
	_play_collect_effect()

func _play_collect_effect():
	# Desactivar el process para que no siga rotando/flotando
	set_process(false)
	
	# Desactivar el área de forma segura 
	if area:
		area.set_deferred("monitoring", false)
	
	# Crear un Tween para efecto de recogida
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Subir mientras se encoge (pero no hasta 0)
	tween.tween_property(self, "global_position:y", global_position.y + 1.0, 0.5)
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.5)
	
	# Hacer transparente el sprite si existe
	if sprite:
		tween.tween_property(sprite, "modulate:a", 0.0, 0.5)
	
	# Cuando termine, eliminar
	tween.finished.connect(func():
		print("🗑️ HealthPickup: Eliminado de la escena")
		queue_free()
	)
