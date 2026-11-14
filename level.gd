extends Node

const TILE_PATH := "res://art/highway-block.png"   # your PNG
const GROUND_Y := 400.0                   # y of the top surface of the middle road
const GROUND_SCALE := 1.3                 # scale of the ground image
const STRIP_TILES := 40                   # keep this even
const SPAWN_HEIGHT := 150.0               # how far above the ground the player starts
const HITBOX_OFFSET := 220.0              # px to move the ground hitbox down (negative = up)
const LANE_GAP := 0.0                     # px of empty space between roads (0 = stacked edge to edge)
const LANE_TIME_SLOW := 0.7               # seconds a lane change takes at MIN_LANE_SPEED
const LANE_TIME_FAST := 0.15              # seconds a lane change takes at LANE_TOP_SPEED
const LANE_TOP_SPEED := 600.0             # px/s at (and above) which the change is fastest
const MIN_LANE_SPEED := 50.0              # px/s the car must be moving to change lanes
const GAUGE_PATH := "res://art/throttle-gauge.png"
const NEEDLE_PATH := "res://art/throttle-gauge-needle.png"
const HUD_SCALE := 1.0                    # scale for both images
const HUD_PADDING := 24.0                 # px from the left and bottom screen edges
const NEEDLE_INSET := 4.0                 # px of gauge border the needle stays inside, top and bottom
const NEEDLE_X_OFFSET := -20.0            # px shift sideways (negative = left)

@onready var player: CharacterBody2D = $CharacterBody2D

var grounds: Array[StaticBody2D] = []
var lane := 1                             # 0 = top, 1 = middle (start), 2 = bottom
var changing := false
var lane_spacing: float
var tile_w: float
var needle: TextureRect
var needle_top: float
var needle_bottom: float


func _ready() -> void:
	var tex := load(TILE_PATH) as Texture2D
	tile_w = tex.get_width() * GROUND_SCALE
	var tile_h := tex.get_height() * GROUND_SCALE
	var strip_w := tile_w * STRIP_TILES
	lane_spacing = tile_h + LANE_GAP

	for i in 3:
		var g := StaticBody2D.new()
		add_child(g)
		move_child(g, i)  # roads draw behind the player
		g.position = Vector2(0, GROUND_Y + (i - 1) * lane_spacing + tile_h / 2.0)
		g.collision_layer = 1 << (i + 1)   # each lane gets its own physics layer
		g.collision_mask = 0

		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 0, tex.get_width() * STRIP_TILES, tex.get_height())
		sprite.scale = Vector2(GROUND_SCALE, GROUND_SCALE)
		g.add_child(sprite)

		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(strip_w, tile_h)
		shape.shape = rect
		shape.position.y = HITBOX_OFFSET
		g.add_child(shape)

		grounds.append(g)

	player.collision_mask = 1 << (lane + 1)   # car only collides with its current lane
	player.position = Vector2(0, GROUND_Y - SPAWN_HEIGHT)

	# Throttle gauge HUD
	var hud := CanvasLayer.new()
	add_child(hud)

	var gauge_tex := load(GAUGE_PATH) as Texture2D
	var needle_tex := load(NEEDLE_PATH) as Texture2D
	var gw := gauge_tex.get_width() * HUD_SCALE
	var gh := gauge_tex.get_height() * HUD_SCALE
	var nw := needle_tex.get_width() * HUD_SCALE
	var nh := needle_tex.get_height() * HUD_SCALE

	var gauge := TextureRect.new()
	gauge.texture = gauge_tex
	gauge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gauge.stretch_mode = TextureRect.STRETCH_SCALE
	gauge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	gauge.anchor_top = 1.0       # anchor to the bottom-left corner
	gauge.anchor_bottom = 1.0
	gauge.offset_left = HUD_PADDING
	gauge.offset_right = HUD_PADDING + gw
	gauge.offset_top = -HUD_PADDING - gh
	gauge.offset_bottom = -HUD_PADDING
	hud.add_child(gauge)

	needle = TextureRect.new()
	needle.texture = needle_tex
	needle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	needle.stretch_mode = TextureRect.STRETCH_SCALE
	needle.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	gauge.add_child(needle)
	needle.size = Vector2(nw, nh)

	needle_top = NEEDLE_INSET            # gauge y where the needle center sits at 100%
	needle_bottom = gh - NEEDLE_INSET    # gauge y where it sits at 0%
	needle.position.x = (gw - nw) / 2.0 + NEEDLE_X_OFFSET
	needle.position.y = needle_bottom - nh / 2.0


func _physics_process(_delta: float) -> void:
	for g in grounds:
		g.position.x = snappedf(player.position.x, tile_w)

	if not changing and player.is_on_floor() and absf(player.velocity.x) > MIN_LANE_SPEED:
		if Input.is_action_just_pressed("left"):
			_change_lane(-1)
		elif Input.is_action_just_pressed("right"):
			_change_lane(1)

	var t := clampf(float(player.get("power")), 0.0, 1.0)
	needle.position.y = lerpf(needle_bottom, needle_top, t) - needle.size.y / 2.0


func _change_lane(dir: int) -> void:
	var target := lane + dir
	if target < 0 or target > 2:
		return
	changing = true
	lane = target
	player.set("lane_changing", true)
	player.collision_mask = 0   # pass through roads while moving between lanes

	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var speed := clampf(absf(player.velocity.x), MIN_LANE_SPEED, LANE_TOP_SPEED)
	var duration := lerpf(LANE_TIME_SLOW, LANE_TIME_FAST, inverse_lerp(MIN_LANE_SPEED, LANE_TOP_SPEED, speed))
	tween.tween_property(player, "position:y", player.position.y + dir * lane_spacing, duration)
	tween.finished.connect(func():
		player.collision_mask = 1 << (lane + 1)
		player.set("lane_changing", false)
		changing = false
	)
