extends Node3D
## A local-metre world. OSM GeoJSON-like coordinates are [longitude, latitude].
const ORIGIN_LAT := 54.3233
const ORIGIN_LON := 10.1394
const METERS_PER_DEGREE := 111320.0
const DATA_FILE := "res://data/kiel/osm.json"
const PLAYER_SCRIPT = preload("res://scripts/player.gd")
var player: CharacterBody3D
var hud: Label
var show_debug := true
var building_count := 0
var road_count := 0
var source_label := "Demo / offline"
var first_building_position := Vector3.ZERO
var world_bounds := Rect2()
var roof_count := 0
var has_building := false
const CHUNK_SIZE := 256.0
const VISIBLE_RADIUS := 2
var chunk_nodes: Dictionary = {}
var last_chunk := Vector2i(999999, 999999)
var visible_chunks := 0
var terrain_loaded := false
const TERRAIN_FILE := "res://data/kiel/terrain.json"

func _ready() -> void:
    _setup_lighting()
    _create_ground()
    _create_player()
    _create_hud()
    if FileAccess.file_exists(DATA_FILE):
        var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_FILE))
        if parsed is Dictionary and parsed.has("buildings") and parsed.has("roads"):
            source_label = "OpenStreetMap / Kiel"
            _load_osm(parsed)
        else:
            push_warning("Invalid OSM data; using demo layout")
            _demo()
    else:
        _demo()
    _reset_camera()
    _update_chunks(true)

func _reset_camera() -> void:
    if has_building:
        player.global_position = first_building_position + Vector3(0, 75, 105)
    else:
        player.global_position = Vector3(0, 75, 105)
    player.velocity = Vector3.ZERO
    player.flying = true
    player.rotation = Vector3.ZERO
    player.pivot.rotation.x = -0.58

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_HOME:
            _reset_camera()
        elif event.keycode == KEY_F3:
            show_debug = not show_debug
        elif event.keycode == KEY_F11:
            var mode := DisplayServer.window_get_mode()
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _process(_delta: float) -> void:
    _update_chunks()
    hud.visible = show_debug
    if show_debug:
        var p := player.global_position
        var lat := ORIGIN_LAT - p.z / METERS_PER_DEGREE
        var lon := ORIGIN_LON + p.x / (METERS_PER_DEGREE * cos(deg_to_rad(ORIGIN_LAT)))
        hud.text = "EARTH EXPLORER 0.1 | %s\nFPS %d   Buildings %d   Roofs %d   Roads %d   Chunks %d/%d\nXYZ %.1f / %.1f / %.1f m\nGPS %.6f, %.6f\n%s\nWASD move · Mouse look · Shift fast · F fly/walk · Q/E altitude · Space jump/up · F3 HUD · Home reset · Wheel speed · F11 fullscreen · Esc mouse" % [source_label, Engine.get_frames_per_second(), building_count, roof_count, road_count, visible_chunks, chunk_nodes.size(), "GRID" if terrain_loaded else "FLAT", p.x, p.y, p.z, lat, lon, "FLY MODE" if player.flying else "WALK MODE"]

func _geo(lon: float, lat: float) -> Vector3:
    return Vector3((lon - ORIGIN_LON) * METERS_PER_DEGREE * cos(deg_to_rad(ORIGIN_LAT)), 0.0, -(lat - ORIGIN_LAT) * METERS_PER_DEGREE)

func _setup_lighting() -> void:
    var world := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.53, 0.73, 0.93)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.9, 0.95, 1.0)
    env.ambient_light_energy = 0.65
    world.environment = env
    add_child(world)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-50, -25, 0)
    sun.light_energy = 1.15
    add_child(sun)

func _material(color: Color) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 1.0
    return mat

func _chunk_id(pos: Vector3) -> Vector2i:
    return Vector2i(floori(pos.x / CHUNK_SIZE), floori(pos.z / CHUNK_SIZE))

func _chunk_parent(pos: Vector3) -> Node3D:
    var id := _chunk_id(pos)
    if not chunk_nodes.has(id):
        var node := Node3D.new()
        node.name = "Chunk_%d_%d" % [id.x, id.y]
        add_child(node)
        chunk_nodes[id] = node
    return chunk_nodes[id]

func _update_chunks(force := false) -> void:
    if player == null:
        return
    var current := _chunk_id(player.global_position)
    if not force and current == last_chunk:
        return
    last_chunk = current
    visible_chunks = 0
    for id in chunk_nodes:
        var enabled: bool = maxi(abs(id.x - current.x), abs(id.y - current.y)) <= VISIBLE_RADIUS
        var node: Node3D = chunk_nodes[id]
        node.visible = enabled
        for child in node.get_children():
            for body in child.find_children("*", "StaticBody3D", true, false):
                body.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
        if enabled:
            visible_chunks += 1

func _box(parent: Node3D, center: Vector3, size: Vector3, color: Color, collision := false, angle := 0.0) -> void:
    var root := Node3D.new()
    root.position = center
    root.rotation.y = angle
    if parent == self:
        _chunk_parent(center).add_child(root)
    else:
        parent.add_child(root)
    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = size
    mesh.mesh = box
    mesh.material_override = _material(color)
    root.add_child(mesh)
    if collision:
        var body := StaticBody3D.new()
        root.add_child(body)
        var shape := CollisionShape3D.new()
        var box_shape := BoxShape3D.new()
        box_shape.size = size
        shape.shape = box_shape
        body.add_child(shape)

func _create_ground() -> void:
    if FileAccess.file_exists(TERRAIN_FILE):
        var data = JSON.parse_string(FileAccess.get_file_as_string(TERRAIN_FILE))
        if data is Dictionary and _create_height_terrain(data):
            terrain_loaded = true
            return
        push_warning("Terrain file invalid; falling back to flat ground")
    var ground := Node3D.new()
    ground.name = "PermanentGround"
    add_child(ground)
    _box(ground, Vector3(0, -0.5, 0), Vector3(1800, 1, 1800), Color(0.3, 0.47, 0.31), true)

func _create_height_terrain(data: Dictionary) -> bool:
    # Local regular height grid in metres, centred at Godot origin.
    var width := int(data.get("width", 0))
    var depth := int(data.get("depth", 0))
    var step := float(data.get("step_m", 0.0))
    var heights: Array = data.get("heights", [])
    if width < 2 or depth < 2 or width > 513 or depth > 513 or step <= 0.0 or heights.size() != width * depth:
        return false
    var vertices := PackedVector3Array()
    var indices := PackedInt32Array()
    var normals := PackedVector3Array()
    for z in range(depth):
        for x in range(width):
            var px := (float(x) - float(width - 1) * 0.5) * step
            var pz := (float(z) - float(depth - 1) * 0.5) * step
            vertices.append(Vector3(px, float(heights[z * width + x]), pz))
    for z in range(depth - 1):
        for x in range(width - 1):
            var i := z * width + x
            indices.append_array(PackedInt32Array([i, i + width, i + 1, i + 1, i + width, i + width + 1]))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var ground := StaticBody3D.new()
    ground.name = "HeightTerrain"
    add_child(ground)
    var visual := MeshInstance3D.new()
    visual.mesh = mesh
    visual.material_override = _material(Color(0.29, 0.49, 0.31))
    visual.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
    ground.add_child(visual)
    var collision := CollisionShape3D.new()
    collision.shape = mesh.create_trimesh_shape()
    ground.add_child(collision)
    return true

func _create_player() -> void:
    player = CharacterBody3D.new()
    player.set_script(PLAYER_SCRIPT)
    add_child(player)
    player.position = Vector3(0, 90, 0)
    player.pivot.rotation.x = -0.75

func _create_hud() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    hud = Label.new()
    hud.position = Vector2(14, 12)
    hud.add_theme_color_override("font_color", Color.WHITE)
    hud.add_theme_color_override("font_shadow_color", Color.BLACK)
    hud.add_theme_constant_override("shadow_offset_x", 1)
    hud.add_theme_constant_override("shadow_offset_y", 2)
    layer.add_child(hud)

func _load_osm(data: Dictionary) -> void:
    for building in data["buildings"]:
        var raw_points: Array = building.get("points", [])
        if raw_points.size() < 3: continue
        var points: Array[Vector3] = []
        for point in raw_points:
            if point is Array and point.size() >= 2:
                points.append(_geo(float(point[0]), float(point[1])))
        if points.size() < 3: continue
        var height := clampf(float(building.get("height", 10.0)), 2.0, 250.0)
        _building(points, height)
    for road in data["roads"]:
        var raw_points: Array = road.get("points", [])
        if raw_points.size() < 2: continue
        for i in range(raw_points.size() - 1):
            var a: Array = raw_points[i]
            var b: Array = raw_points[i + 1]
            if a.size() < 2 or b.size() < 2: continue
            _segment(_geo(float(a[0]), float(a[1])), _geo(float(b[0]), float(b[1])), 0.08, 4.5, Color(0.19, 0.21, 0.23), false)
        road_count += 1

func _segment(a: Vector3, b: Vector3, y: float, width: float, color: Color, collision: bool) -> void:
    var delta := b - a
    var length := delta.length()
    if length < 0.1: return
    _box(self, (a + b) * 0.5 + Vector3.UP * y, Vector3(width, 0.12 if not collision else y * 2.0, length), color, collision, atan2(delta.x, delta.z))

func _building(points: Array[Vector3], height: float) -> void:
    # Extrude real OSM footprints, including concave polygons, and cap with a roof.
    if points.size() < 3:
        return
    var outline := PackedVector2Array()
    var center := Vector3.ZERO
    for point in points:
        outline.append(Vector2(point.x, point.z))
        center += point
    center /= float(points.size())
    # Godot's triangulator requires a simple polygon. Invalid footprints keep their walls.
    var triangles := Geometry2D.triangulate_polygon(outline)
    if triangles.size() >= 3:
        var vertices := PackedVector3Array()
        var indices := PackedInt32Array()
        for point in points:
            vertices.append(Vector3(point.x, height, point.z))
        for t in range(0, triangles.size(), 3):
            # Make both sides visible, regardless of polygon winding.
            var i0 := triangles[t]
            var i1 := triangles[t + 1]
            var i2 := triangles[t + 2]
            indices.append_array(PackedInt32Array([i0, i1, i2, i2, i1, i0]))
        var arrays := []
        arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX] = vertices
        arrays[Mesh.ARRAY_INDEX] = indices
        var roof_mesh := ArrayMesh.new()
        roof_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        var roof := MeshInstance3D.new()
        roof.mesh = roof_mesh
        roof.material_override = _material(Color(0.48, 0.29, 0.24))
        _chunk_parent(center).add_child(roof)
        roof_count += 1
    for i in range(points.size()):
        _segment(points[i], points[(i + 1) % points.size()], height * 0.5, 0.22, Color(0.79, 0.76, 0.70), true)
    if not has_building:
        first_building_position = center
        has_building = true
    building_count += 1

func _demo() -> void:
    for x in range(-3, 4):
        for z in range(-3, 4):
            if (x + z) % 3 == 0: continue
            var center := Vector3(x * 70.0, 0, z * 70.0)
            var half := 13.0
            _building([center + Vector3(-half, 0, -half), center + Vector3(half, 0, -half), center + Vector3(half, 0, half), center + Vector3(-half, 0, half)], 12.0 + float(abs(x + z) % 4) * 6.0)
    for n in range(-3, 4):
        _segment(Vector3(-300, 0, n * 70.0 + 35), Vector3(300, 0, n * 70.0 + 35), 0.07, 7.0, Color(0.2, 0.21, 0.23), false)
        _segment(Vector3(n * 70.0 + 35, 0, -300), Vector3(n * 70.0 + 35, 0, 300), 0.07, 7.0, Color(0.2, 0.21, 0.23), false)
        road_count += 2
