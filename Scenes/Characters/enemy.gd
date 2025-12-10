extends CharacterBody3D
class_name Enemy

## Script base para enemigos. Los behaviors son opcionales y modulares.

@export var max_hp: int = 30
@export var defense: int = 0

var current_hp: int
var is_alive: bool = true
var is_taking_damage: bool = false

@onready var animated_sprite = $AnimatedSprite3D
@onready var collision_shape = $CollisionShape3D

func _ready():
	current_hp = max_hp
	_play_default_animation()

func _physics_process(delta):
	# Aplicar gravedad si no está en el suelo
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	
	# Los behaviors manejan su propio movimiento
	# El enemy solo ejecuta move_and_slide() si tiene velocity
	if velocity.length() > 0:
		move_and_slide()

func take_damage(damage: int):
	if not is_alive:
		return
	
	var final_damage = max(damage - defense, 0)
	current_hp -= final_damage
	
	print("Enemigo HP: ", current_hp, "/", max_hp)
	
	if current_hp <= 0:
		die()
	else:
		if not is_taking_damage:
			play_damage_animation()

func play_damage_animation():
	is_taking_damage = true
	
	# Notificar a todos los behaviors que se detenga
	_notify_behaviors("pause")
	
	if animated_sprite.sprite_frames.has_animation("damage"):
		animated_sprite.play("damage")
		await get_tree().create_timer(0.3).timeout
		_on_damage_animation_finished()
	else:
		_flash_red()

func _flash_red():
	animated_sprite.modulate = Color(1, 0.3, 0.3)
	await get_tree().create_timer(0.1).timeout
	animated_sprite.modulate = Color.WHITE
	_on_damage_animation_finished()

func _on_damage_animation_finished():
	is_taking_damage = false
	
	if is_alive:
		# Notificar a todos los behaviors que reanuden
		_notify_behaviors("resume")
		_play_default_animation()

func die():
	if not is_alive:
		return
		
	is_alive = false
	
	print("💀 ENEMIGO ELIMINADO")
	
	# Notificar a todos los behaviors que se detengan
	_notify_behaviors("stop")
	
	set_physics_process(false)
	
	if collision_shape:
		collision_shape.set_deferred("disabled", true)

	if animated_sprite.sprite_frames.has_animation("death"):
		animated_sprite.play("death")
		await get_tree().create_timer(0.5).timeout
	else:
		var tween = create_tween()
		tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.5)
		await tween.finished
	
	queue_free()

# ========== FUNCIONES AUXILIARES PARA BEHAVIORS ==========

func _notify_behaviors(action: String):
	# Buscar todos los behaviors hijos y llamar sus métodos
	for child in get_children():
		match action:
			"pause":
				if child.has_method("pause"):
					child.pause()
			"resume":
				if child.has_method("resume"):
					child.resume()
			"stop":
				if child.has_method("stop"):
					child.stop()
				if child.has_method("set_physics_process"):
					child.set_physics_process(false)

func _play_default_animation():
	# Intentar reproducir la animación más apropiada
	if animated_sprite.sprite_frames.has_animation("walk"):
		animated_sprite.play("walk")
	elif animated_sprite.sprite_frames.has_animation("idle"):
		animated_sprite.play("idle")

# Función para que behaviors puedan voltear el sprite
func flip_sprite(facing_right: bool):
	if animated_sprite:
		animated_sprite.flip_h = not facing_right
