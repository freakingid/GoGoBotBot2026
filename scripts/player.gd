extends CharacterBody2D

# Prototype Slice 0.1:
# - Movement (accel/friction/max speed)
# - Aim (KB+Mouse / KB-only 4-key / Controller)
# - Auto-fire when aim magnitude > deadzone (no fire button)
# - Projectile cap (simple runtime bullets, no pooling yet)

enum InputMode { CONTROLLER, KB_MOUSE, KB_KEYS }

@export var input_mode: InputMode = InputMode.KB_MOUSE

# Movement tuning (starter values)
@export var max_speed: float = 330.0
@export var accel: float = 2400.0
@export var friction: float = 2800.0

# Aim / firing tuning (starter values)
@export var aim_deadzone: float = 0.20
@export var mouse_deadzone_px: float = 18.0
@export var fire_rate: float = 10.0 # shots/sec
@export var projectile_speed: float = 900.0
@export var projectile_lifetime: float = 0.9
@export var projectile_cap: int = 2

var _aim_vec: Vector2 = Vector2.ZERO
var _fire_cooldown: float = 0.0
var _active_projectiles: int = 0

@onready var _muzzle: Node2D = get_node_or_null("Muzzle")
@onready var _camera: Camera2D = get_node_or_null("Camera2D")


func _ready() -> void:
	# Ensure the player's Camera2D becomes active.
	if _camera != null:
		_camera.make_current()

	# Minimal InputMap setup so the project runs even if Input Map isn't configured yet.
	_ensure_action("move_left")
	_ensure_action("move_right")
	_ensure_action("move_up")
	_ensure_action("move_down")
	_ensure_action("aim_left")
	_ensure_action("aim_right")
	_ensure_action("aim_up")
	_ensure_action("aim_down")
	_ensure_action("pause")

	# Movement keys (WASD + arrows)
	_bind_key("move_left", KEY_A)
	_bind_key("move_left", KEY_LEFT)
	_bind_key("move_right", KEY_D)
	_bind_key("move_right", KEY_RIGHT)
	_bind_key("move_up", KEY_W)
	_bind_key("move_up", KEY_UP)
	_bind_key("move_down", KEY_S)
	_bind_key("move_down", KEY_DOWN)

	# KB-aim keys: IJKL + P ' ; L (preference: P';L)
	_bind_key("aim_left", KEY_J)
	_bind_key("aim_right", KEY_L)
	_bind_key("aim_up", KEY_I)
	_bind_key("aim_down", KEY_K)

	_bind_key("aim_left", KEY_P)
	_bind_key("aim_right", KEY_L)
	_bind_key("aim_up", KEY_APOSTROPHE)   # '
	_bind_key("aim_down", KEY_SEMICOLON)  # ;

	_bind_key("pause", KEY_ESCAPE)

	# Controller axes (left stick = move, right stick = aim)
	_bind_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_bind_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_bind_joy_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_bind_joy_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_bind_joy_axis("aim_left", JOY_AXIS_RIGHT_X, -1.0)
	_bind_joy_axis("aim_right", JOY_AXIS_RIGHT_X, 1.0)
	_bind_joy_axis("aim_up", JOY_AXIS_RIGHT_Y, -1.0)
	_bind_joy_axis("aim_down", JOY_AXIS_RIGHT_Y, 1.0)


func _physics_process(delta: float) -> void:
	_update_movement(delta)
	_update_aim()
	_update_autofire(delta)


func _update_movement(delta: float) -> void:
	var move_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if move_input != Vector2.ZERO:
		var desired := move_input * max_speed
		velocity = velocity.move_toward(desired, accel * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()


func _update_aim() -> void:
	match input_mode:
		InputMode.KB_MOUSE:
			var to_mouse := get_global_mouse_position() - global_position
			if to_mouse.length() < mouse_deadzone_px:
				_aim_vec = Vector2.ZERO
			else:
				_aim_vec = to_mouse.normalized()
		InputMode.KB_KEYS:
			_aim_vec = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
		InputMode.CONTROLLER:
			_aim_vec = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")

	if _aim_vec.length() < aim_deadzone:
		_aim_vec = Vector2.ZERO
	else:
		_aim_vec = _aim_vec.normalized()


func _update_autofire(delta: float) -> void:
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)

	if _aim_vec == Vector2.ZERO:
		return
	if _fire_cooldown > 0.0:
		return
	if _active_projectiles >= projectile_cap:
		return

	_spawn_bullet(_aim_vec)
	_fire_cooldown = 1.0 / maxf(0.001, fire_rate)


func _spawn_bullet(dir: Vector2) -> void:
	var spawn_pos := global_position
	if _muzzle != null:
		spawn_pos = _muzzle.global_position

	var bullet := _Bullet.new()
	bullet.global_position = spawn_pos
	bullet.direction = dir.normalized()
	bullet.speed = projectile_speed
	bullet.lifetime = projectile_lifetime

	# Add to the current scene so bullets don't inherit player transforms.
	var parent_node: Node = get_tree().current_scene
	if parent_node == null:
		parent_node = get_tree().root
	parent_node.add_child(bullet)

	_active_projectiles += 1
	bullet.tree_exited.connect(_on_bullet_tree_exited)


func _on_bullet_tree_exited() -> void:
	_active_projectiles = maxi(0, _active_projectiles - 1)


func _ensure_action(action_name: StringName) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)


func _bind_key(action_name: StringName, keycode: Key) -> void:
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventKey and ev.keycode == keycode:
			return
	var e := InputEventKey.new()
	e.keycode = keycode
	InputMap.action_add_event(action_name, e)


func _bind_joy_axis(action_name: StringName, axis: JoyAxis, axis_value_sign: float) -> void:
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventJoypadMotion and ev.axis == axis and signf(ev.axis_value) == signf(axis_value_sign):
			return
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = axis_value_sign
	InputMap.action_add_event(action_name, e)


class _Bullet:
	extends Area2D

	var direction: Vector2 = Vector2.RIGHT
	var speed: float = 900.0
	var lifetime: float = 0.9

	var _age: float = 0.0

	func _init() -> void:
		# Minimal collision so we can hook hits later.
		var cs := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 4.0
		cs.shape = shape
		add_child(cs)

		monitoring = true
		monitorable = true

	func _physics_process(delta: float) -> void:
		global_position += direction * speed * delta
		_age += delta
		if _age >= lifetime:
			queue_free()
