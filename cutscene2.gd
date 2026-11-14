extends Node

const NEXT_SCENE := "res://main.tscn"
const BG_PATH := "res://art/hell.png"
const TILE_PATH := "res://art/highway-block-hell.png"
const GROUND_SCALE := 1.3                # keep the same as level.gd
const STRIP_TILES := 40                  # keep the same as level.gd
const HITBOX_OFFSET := 220.0             # keep the same as level.gd
const CUTSCENE_SCALE := 0.6              # shrinks the road and car together (1.0 = same size as the game)
const WAIT_BEFORE := 2.0                 # seconds of empty road before the car
const WAIT_AFTER := 2.0                  # seconds of empty road after the car
const FADE_IN_TIME := 0.5
const FADE_OUT_TIME := 0.6
const CAR_START_MARGIN := 800.0          # px left of the screen where the car waits
const CAR_END_MARGIN := 400.0            # px right of the screen where it counts as gone
const SPAWN_HEIGHT := 150.0              # same drop height as level.gd

var car: CharacterBody2D
var fade: ColorRect
var size: Vector2
var center: Vector2


func _ready() -> void:
	size = get_viewport().get_visible_rect().size
	center = size / 2.0

	# Background, stretched over the whole screen
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	var bg := TextureRect.new()
	bg.texture = load(BG_PATH) as Texture2D
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_layer.add_child(bg)

	# Fixed camera
	var cam := Camera2D.new()
	cam.position = center
	add_child(cam)

	# One road lane near the bottom of the screen
	var tex := load(TILE_PATH) as Texture2D
	var ground_scale := GROUND_SCALE * CUTSCENE_SCALE
	var tile_w := tex.get_width() * ground_scale
	var tile_h := tex.get_height() * ground_scale
	var ground_y := size.y - tile_h                # road image bottom sits on the window bottom
	var rest_y := ground_y + HITBOX_OFFSET * CUTSCENE_SCALE   # where the car's wheels touch

	var road := StaticBody2D.new()
	road.position = Vector2(center.x, ground_y + tile_h / 2.0)
	add_child(road)

	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, tex.get_width() * STRIP_TILES, tex.get_height())
	sprite.scale = Vector2(ground_scale, ground_scale)
	road.add_child(sprite)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(tile_w * STRIP_TILES, tile_h)
	shape.shape = rect
	shape.position.y = HITBOX_OFFSET * CUTSCENE_SCALE
	road.add_child(shape)

	# Borrow the car from main.tscn so it has the same sprite, wheels and physics
	var main_scene := (load(NEXT_SCENE) as PackedScene).instantiate()
	car = main_scene.get_node("CharacterBody2D") as CharacterBody2D
	main_scene.remove_child(car)
	main_scene.free()
	var old_cam := car.get_node_or_null("Camera2D")
	if old_cam:
		car.remove_child(old_cam)
		old_cam.free()

	car.set("cutscene", true)                      # no player control
	car.set("cutscene_throttle", 0.0)              # just settle on the road for now
	car.collision_mask = 1
	car.scale = Vector2(CUTSCENE_SCALE, CUTSCENE_SCALE)
	car.position = Vector2(center.x - size.x / 2.0 - CAR_START_MARGIN, rest_y - SPAWN_HEIGHT * CUTSCENE_SCALE)
	add_child(car)

	# Black overlay for fading
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 100
	add_child(fade_layer)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(fade)

	_run()


func _run() -> void:
	create_tween().tween_property(fade, "color:a", 0.0, FADE_IN_TIME)

	# Empty road (the car is waiting off-screen to the left)
	await get_tree().create_timer(WAIT_BEFORE).timeout

	# Full throttle, already at top speed, then drive past
	car.set("cutscene_throttle", 1.0)
	car.velocity.x = _top_speed()
	var right_edge := center.x + size.x / 2.0 + CAR_END_MARGIN
	while car.position.x < right_edge:
		await get_tree().physics_frame
	car.visible = false

	# Empty road again, then fade out and go back
	await get_tree().create_timer(WAIT_AFTER).timeout
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, FADE_OUT_TIME)
	await tween.finished
	get_tree().change_scene_to_file(NEXT_SCENE)


func _top_speed() -> float:
	var c: Dictionary = car.get_script().get_script_constant_map()
	return sqrt(float(c["ENGINE_ACCEL"]) / float(c["DRAG"]))
