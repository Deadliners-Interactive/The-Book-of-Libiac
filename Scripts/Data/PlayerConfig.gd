## Player tunable configuration resource.
## Allows balancing player stats without editing player.gd.
extends Resource
class_name PlayerConfig

# ==============================================================================
# Movement
# ==============================================================================

@export var move_speed: float = 5.0
@export var jump_speed: float = 6.0
@export var gravity_multiplier: float = 2.0
@export var use_jump_model: bool = false
@export var jump_height: float = 0.42
@export var time_to_jump_apex: float = 0.18
@export var jump_coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12
@export var fall_gravity_multiplier: float = 1.2
@export var jump_release_gravity_multiplier: float = 1.4
@export var air_animation_delay: float = 0.08
@export var ground_snap_length: float = 0.6
@export var max_floor_angle_degrees: float = 58.0
@export var floor_stop_on_slope: bool = false
@export var floor_constant_speed: bool = true
@export var collision_safe_margin: float = 0.001

# ==============================================================================
# Edge Hop
# ==============================================================================

@export var edge_hop_enabled: bool = true
@export var edge_hop_forward_distance: float = 0.11
@export var edge_hop_probe_height: float = 0.18
@export var edge_hop_probe_depth: float = 0.9
@export var edge_hop_forward_boost: float = 2.15
@export var edge_hop_vertical_boost: float = 1.75
@export var edge_hop_cooldown: float = 0.16
@export var edge_hop_step_down_threshold: float = 0.07

# ==============================================================================
# Combat
# ==============================================================================

@export var attack_damage: int = 10
@export var attack_movement_multiplier: float = 0.6
@export var attack_hit_delay: float = 0.1

# ==============================================================================
# Health
# ==============================================================================

@export var max_health: float = 30.0
@export var invulnerability_time: float = 1.0
@export var damage_visual_time: float = 0.5

# ==============================================================================
# Roll
# ==============================================================================

@export var roll_speed: float = 8.0
@export var roll_duration: float = 0.45
@export var roll_cooldown: float = 0.2

# ==============================================================================
# FSM Transitions
# ==============================================================================

@export_group("FSM Transitions")
@export var allow_normal_to_attacking: bool = true
@export var allow_normal_to_rolling: bool = true
@export var allow_normal_to_damage: bool = true

@export var allow_attacking_to_normal: bool = true
@export var allow_attacking_to_rolling: bool = true
@export var allow_attacking_to_damage: bool = true

@export var allow_rolling_to_normal: bool = true
@export var allow_rolling_to_damage: bool = true

@export var allow_damage_to_normal: bool = true
