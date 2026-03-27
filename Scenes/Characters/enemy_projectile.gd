extends Area3D

# Configuración del proyectil (dejamos estas variables como estaban)
var direction: Vector3 = Vector3.FORWARD
var speed: float = 8.0
var damage: float = 5.0
var max_lifetime: float = 3.0
var shooter_ref: Node3D = null

func _ready():
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(max_lifetime).timeout.connect(queue_free)

func initialize(dir: Vector3, spd: float, dmg: float, shooter: Node3D):
	direction = dir.normalized()
	speed = spd
	damage = dmg
	shooter_ref = shooter
	look_at(global_position + direction) 

func _process(delta):
	global_position += direction * speed * delta

func _on_body_entered(body: Node3D):
	# 🛑 1. IGNORAR AL QUE DISPARÓ
	if body == shooter_ref:
		return
		
	# 🟢 2. COLISIÓN CON EL JUGADOR: Aplica daño y knockback
	if body.is_in_group("player"):
		if body.has_method("take_damage_hearts_with_knockback"):
			# 💡 CAMBIO CLAVE: Reducimos la fuerza del knockback de 0.5 a un valor muy pequeño (ej. 0.05).
			var knockback_force = 0.05 
			body.take_damage_hearts_with_knockback(damage, direction, knockback_force)
			
		queue_free()
		
	# 🟡 3. COLISIÓN CON EL ENTORNO
	if not body.is_in_group("player") and not body.is_in_group("enemy"):
		queue_free()
