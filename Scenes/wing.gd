# Wing.gd - Item que añade un contenedor de vida extra (+10 HP)
# Este script va en el Node3D raíz
extends Node3D

@export var health_increase: float = 10.0
@export var enable_rotation: bool = false  # Nuevo: controla si rota
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
	print("🪽 Wing: Inicializando item de vida extra...")
	
	# Guardar posición inicial
	start_y = global_position.y
	
	# Configurar el sprite si existe (solo si use_billboard está activado)
	if sprite and use_billboard:
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.pixel_size = 0.01
	
	# Configurar Area3D
	if area:
		area.monitoring = true
		area.monitorable = true
		
		# Conectar señal
		if not area.body_entered.is_connected(_on_body_entered):
			area.body_entered.connect(_on_body_entered)
	else:
		push_error("🪽 Wing: No se encontró Area3D!")
		return
	
	print("✅ Wing: Lista para ser recogida")

func _process(delta):
	if collected:
		return
	
	time_passed += delta
	
	# Rotación constante del nodo completo (solo si está habilitado)
	if enable_rotation:
		rotate_y(rotation_speed * delta)
	
	# Movimiento de "flotación" arriba y abajo
	var new_y = start_y + sin(time_passed * bob_speed) * bob_height
	global_position.y = new_y

func _on_body_entered(body: Node):
	if collected:
		return
	
	# Solo jugadores
	if not body.is_in_group("player"):
		return
	
	# Verificar que tiene el método
	if not body.has_method("increase_max_health"):
		push_warning("🪽 Wing: El player no tiene el método increase_max_health()")
		return
	
	# Aplicar el aumento de vida
	collected = true
	body.increase_max_health(health_increase)
	
	print("🪽 Wing: ¡Recogida! +%.1f HP máximos" % health_increase)
	
	# Efecto de recogida
	_play_collect_effect()

func _play_collect_effect():
	# Desactivar el process para que no siga rotando/flotando
	set_process(false)
	
	# Desactivar el área de forma segura (deferred)
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
		print("🗑️ Wing: Eliminada de la escena")
		queue_free()
	)
