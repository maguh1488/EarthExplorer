extends CharacterBody3D
## Free-flying first-person explorer with walking and collision support.
const WALK_SPEED := 6.0
const RUN_SPEED := 13.0
const FLY_SPEED := 24.0
const MOUSE_SENSITIVITY := 0.0025
var flying := true
var fly_speed_multiplier := 1.0
var pivot: Node3D

func _ready() -> void:
    name = "Player"
    var shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.35
    capsule.height = 1.8
    shape.shape = capsule
    shape.position.y = 0.9
    add_child(shape)
    pivot = Node3D.new()
    pivot.position.y = 1.6
    add_child(pivot)
    var camera := Camera3D.new()
    camera.current = true
    camera.far = 2500.0
    pivot.add_child(camera)
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
        pivot.rotation.x = clampf(pivot.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -1.5, 1.5)
    elif event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            fly_speed_multiplier = clampf(fly_speed_multiplier * 1.25, 0.2, 12.0)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            fly_speed_multiplier = clampf(fly_speed_multiplier / 1.25, 0.2, 12.0)
    elif event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
        elif event.keycode == KEY_F:
            flying = not flying
            velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
    var axis := Vector2.ZERO
    if Input.is_key_pressed(KEY_A): axis.x -= 1.0
    if Input.is_key_pressed(KEY_D): axis.x += 1.0
    if Input.is_key_pressed(KEY_W): axis.y -= 1.0
    if Input.is_key_pressed(KEY_S): axis.y += 1.0
    axis = axis.normalized()
    var speed := RUN_SPEED if Input.is_key_pressed(KEY_SHIFT) else WALK_SPEED
    var direction := global_transform.basis * Vector3(axis.x, 0.0, axis.y)
    if flying:
        speed = FLY_SPEED * fly_speed_multiplier * (2.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
        direction = pivot.global_transform.basis * Vector3(axis.x, 0.0, axis.y)
        if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE): direction.y += 1.0
        if Input.is_key_pressed(KEY_Q): direction.y -= 1.0
        velocity = direction.normalized() * speed
    else:
        velocity.x = direction.x * speed
        velocity.z = direction.z * speed
        if not is_on_floor(): velocity.y -= 9.81 * delta
        elif Input.is_key_pressed(KEY_SPACE): velocity.y = 5.5
    move_and_slide()
