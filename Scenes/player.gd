extends CharacterBody3D

@export var move_speed: float = 1.0
@export var jump_speed: float = 2.0
@export var attack_damage: int = 10
@export var attack_movement_multiplier: float = 0.6
@export var roll_speed: float = 4.0
@export var roll_duration: float = 0.4
@export var roll_cooldown: float = 0.2

var is_facing_right = true
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var can_attack = true
var is_attacking = false
var attack_queued = false  # Para detectar clicks mientras ataca
var attack_forward = true  # true = adelante, false = reversa
var is_rolling = false
var can_roll = true
var roll_direction = Vector3.ZERO
var roll_queued = false  # Para encolar siguiente roll

@onready var animated_sprite = $Sprite3D
@onready var attack_area = $AttackArea
@onready var attack_collision = $AttackArea/CollisionShape3D

func _ready():
	# Desactivar el área de ataque al inicio
	attack_collision.disabled = true

func _physics_process(delta):
	if not is_rolling:
		jump(delta)
		move()
		flip()
	else:
		# Durante el roll, mantener la dirección y velocidad
		velocity.x = roll_direction.x * roll_speed
		velocity.z = roll_direction.z * roll_speed
		# Aplicar gravedad
		if not is_on_floor():
			velocity.y -= gravity * delta
	
	move_and_slide()
	update_animations()
	
	# Input de ataque - NO permitir durante roll
	if Input.is_action_just_pressed("attack") and is_on_floor() and not is_rolling:
		if can_attack and not is_attacking:
			attack()
		elif is_attacking:
			# Si está atacando, encolar siguiente ataque
			attack_queued = true
	
	# Input de roll - PUEDE cancelar ataque (estilo Dark Souls)
	if Input.is_action_just_pressed("roll") and is_on_floor():
		if can_roll and not is_rolling:
			# Si está atacando, cancelar el ataque
			if is_attacking:
				_cancel_attack()
			roll()
		elif is_rolling:
			# Si está en roll, encolar siguiente roll
			roll_queued = true

func update_animations():
	# Prioridad a animación de roll
	if is_rolling:
		return
	
	# Prioridad a animación de ataque
	if is_attacking and animated_sprite.animation == "attack" and animated_sprite.is_playing():
		return
		
	if not is_on_floor():
		# Acelerar animaciones de salto/caída
		animated_sprite.speed_scale = 2.0
		if velocity.y < 0:
			animated_sprite.play("jump")
		else: 
			animated_sprite.play("fall")
		return
	
	# Velocidad normal para animaciones en suelo
	animated_sprite.speed_scale = 1.0
	if velocity.x != 0 or velocity.z != 0:
		animated_sprite.play("run")
	else:
		animated_sprite.play("idle")

func jump(delta):
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_speed
		
	if not is_on_floor():
		velocity.y -= gravity * delta

func move():
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Reducir velocidad durante ataque pero permitir movimiento
	var current_speed = move_speed
	if is_attacking:
		current_speed *= attack_movement_multiplier
	
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

func flip():
	if (is_facing_right and velocity.x < 0) or (not is_facing_right and velocity.x > 0):
		$Sprite3D.scale.x *= -1
		is_facing_right = not is_facing_right

func attack():
	# Cancelar cualquier roll encolado
	roll_queued = false
	
	is_attacking = true
	can_attack = false
	
	# Reproducir animación de ataque con efecto ping-pong
	if animated_sprite.sprite_frames.has_animation("attack"):
		# Acelerar la animación x2
		animated_sprite.speed_scale = 2.0
		
		# Alternar entre adelante y reversa
		if attack_forward:
			animated_sprite.play("attack")
		else:
			animated_sprite.play_backwards("attack")
		
		# Conectar señal de fin de animación si no está conectada
		if not animated_sprite.animation_finished.is_connected(_on_attack_animation_finished):
			animated_sprite.animation_finished.connect(_on_attack_animation_finished)
	
	# Activar hitbox
	attack_collision.disabled = false
	
	# Detectar enemigos en el área (frame del golpe)
	await get_tree().create_timer(0.1).timeout
	var enemies = attack_area.get_overlapping_bodies()
	for enemy in enemies:
		if enemy.has_method("take_damage"):
			enemy.take_damage(attack_damage)
			print("¡Golpe! Daño infligido: ", attack_damage)
	
	# Desactivar hitbox
	await get_tree().create_timer(0.1).timeout
	attack_collision.disabled = true

func _on_attack_animation_finished():
	# Solo reaccionar si era la animación de ataque
	if animated_sprite.animation == "attack":
		# Restaurar velocidad normal de animaciones
		animated_sprite.speed_scale = 1.0
		is_attacking = false
		can_attack = true
		
		# Alternar dirección para el próximo ataque (efecto ping-pong)
		attack_forward = not attack_forward
		
		# Si hay ataque encolado, ejecutarlo INMEDIATAMENTE
		if attack_queued:
			attack_queued = false
			attack()

func roll():
	# Cancelar cualquier ataque encolado
	attack_queued = false
	
	is_rolling = true
	can_roll = false
	
	# Determinar dirección del roll basado en input o dirección que mira
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	if input_dir.length() > 0:
		# Roll en la dirección del movimiento
		roll_direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	else:
		# Roll en la dirección que mira el personaje
		# Si is_facing_right es true, mira a la IZQUIERDA (porque el sprite está volteado)
		# Si is_facing_right es false, mira a la DERECHA
		roll_direction = Vector3(1 if is_facing_right else -1, 0, 0)
	
	# Reproducir animación de roll si existe
	if animated_sprite.sprite_frames.has_animation("roll"):
		animated_sprite.speed_scale = 2.0
		animated_sprite.play("roll")
		# Conectar señal de fin de animación si no está conectada
		if not animated_sprite.animation_finished.is_connected(_on_roll_animation_finished):
			animated_sprite.animation_finished.connect(_on_roll_animation_finished)
	else:
		# Si no hay animación, usar temporizador
		await get_tree().create_timer(roll_duration).timeout
		_finish_roll()

func _on_roll_animation_finished():
	# Solo reaccionar si era la animación de roll
	if animated_sprite.animation == "roll":
		_finish_roll()

func _finish_roll():
	# Restaurar velocidad normal de animaciones
	animated_sprite.speed_scale = 1.0
	is_rolling = false
	
	# Pequeño cooldown antes de poder hacer otro roll
	await get_tree().create_timer(roll_cooldown).timeout
	can_roll = true
	
	# Si hay roll encolado, ejecutarlo después del cooldown
	if roll_queued:
		roll_queued = false
		roll()

func _cancel_attack():
	# Cancelar ataque en progreso
	is_attacking = false
	can_attack = true
	attack_queued = false
	attack_collision.disabled = true
	animated_sprite.speed_scale = 1.0
	print("¡Ataque cancelado! Esquivando...")
