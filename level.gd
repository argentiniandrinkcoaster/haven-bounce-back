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
const BG_COLOR := Color("07ce7c")         # background color of the normal game
const GRASS_PATH := "res://art/grass-durr.png"
const GRASS_SCALE := 1.0                  # grass tile size (raise for bigger grass)
const POINTS_PER_SECOND := 10.0           # points earned each second the car is moving
const SLIME_PATH := "res://art/slime.png"
const SLIME_SCALE := 0.5                  # slime size (smaller = smaller slime)
const SLIME_CHANCE := 0.03                # chance a slime spawns on each new road tile (0.03 = 3%)
const SLIME_FLING := 1200.0               # upward speed the car is flung at
const HIT_FADE_DELAY := 0.6               # seconds in the air before the fade starts
const HIT_FADE_TIME := 0.8                # seconds the fade to black takes
const CUTSCENE_SCENE := "res://cutscene.tscn"

@onready var player: CharacterBody2D = $CharacterBody2D

var grounds: Array[StaticBody2D] = []
var lane := 1                             # 0 = top, 1 = middle (start), 2 = bottom
var changing := false
var lane_spacing: float
var tile_w: float
var grass: Sprite2D
var grass_w: float
var needle: TextureRect
var needle_top: float
var needle_bottom: float
var slime_tex: Texture2D
var slimes: Array[Area2D] = []
var next_tile := 4                        # next road tile to roll a slime for (skips the start)
var spawn_ahead := 8                      # how many tiles ahead of the car to spawn, set in _ready
var hit := false
var score := 0.0
var score_label: Label
var lane_tween: Tween
var fade: ColorRect


func _ready() -> void:
	var tex := load(TILE_PATH) as Texture2D
	tile_w = tex.get_width() * GROUND_SCALE
	var tile_h := tex.get_height() * GROUND_SCALE
	var strip_w := tile_w * STRIP_TILES
	lane_spacing = tile_h + LANE_GAP

	# Solid background color, drawn behind everything
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(bg)

	# Tiling grass that sits still in the world, so it rushes past as you drive
	var grass_tex := load(GRASS_PATH) as Texture2D
	var view := get_viewport().get_visible_rect().size
	var gtw := grass_tex.get_width()
	var gth := grass_tex.get_height()
	var cols := int(ceil(view.x * 3.0 / (gtw * GRASS_SCALE)))
	var rows := int(ceil(view.y * 6.0 / (gth * GRASS_SCALE)))
	grass = Sprite2D.new()
	grass.texture = grass_tex
	grass.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	grass.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	grass.region_enabled = true
	grass.region_rect = Rect2(0, 0, gtw * cols, gth * rows)
	grass.scale = Vector2(GRASS_SCALE, GRASS_SCALE)
	grass.z_index = -10                        # always behind the roads
	grass.position = Vector2(0, GROUND_Y)
	add_child(grass)
	grass_w = gtw * GRASS_SCALE

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

	# Points display (top right)
	var score_layer := CanvasLayer.new()
	score_layer.layer = 2
	add_child(score_layer)
	score_label = Label.new()
	score_label.text = "Points: 0"
	score_label.anchor_left = 1.0
	score_label.anchor_right = 1.0
	score_label.offset_left = -400.0
	score_label.offset_right = -HUD_PADDING
	score_label.offset_top = HUD_PADDING
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.add_theme_font_size_override("font_size", 32)
	score_label.add_theme_color_override("font_outline_color", Color.BLACK)
	score_label.add_theme_constant_override("outline_size", 6)
	score_layer.add_child(score_label)

	# Fade overlay used after hitting a slime
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 100
	add_child(fade_layer)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(fade)

	slime_tex = load(SLIME_PATH) as Texture2D
	spawn_ahead = int(ceil(get_viewport().get_visible_rect().size.x / tile_w)) + 3


func _physics_process(delta: float) -> void:
	# Points for every second spent driving
	if not hit and absf(player.velocity.x) > MIN_LANE_SPEED:
		score += POINTS_PER_SECOND * delta
		score_label.text = "Points: %d" % int(score)

	for g in grounds:
		g.position.x = snappedf(player.position.x, tile_w)
	grass.position.x = snappedf(player.position.x, grass_w)   # jumps by whole tiles, so it's invisible

	# Roll for slimes on road tiles ahead of the car
	var front := int(floor(player.position.x / tile_w)) + spawn_ahead
	while next_tile <= front:
		if randf() < SLIME_CHANCE:
			_spawn_slime(next_tile * tile_w + randf() * tile_w, randi() % 3)
		next_tile += 1

	# Remove slimes that are well behind the car
	var behind := player.position.x - get_viewport().get_visible_rect().size.x - tile_w * 2.0
	for sl in slimes.duplicate():
		if sl.position.x < behind:
			slimes.erase(sl)
			sl.queue_free()

	if not changing and not hit and player.is_on_floor() and absf(player.velocity.x) > MIN_LANE_SPEED:
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
	lane_tween = tween
	var speed := clampf(absf(player.velocity.x), MIN_LANE_SPEED, LANE_TOP_SPEED)
	var duration := lerpf(LANE_TIME_SLOW, LANE_TIME_FAST, inverse_lerp(MIN_LANE_SPEED, LANE_TOP_SPEED, speed))
	tween.tween_property(player, "position:y", player.position.y + dir * lane_spacing, duration)
	tween.finished.connect(func():
		player.collision_mask = 1 << (lane + 1)
		player.set("lane_changing", false)
		changing = false
	)


func _spawn_slime(x: float, slime_lane: int) -> void:
	var w := slime_tex.get_width() * SLIME_SCALE
	var h := slime_tex.get_height() * SLIME_SCALE
	var surface_y := GROUND_Y + (slime_lane - 1) * lane_spacing + HITBOX_OFFSET

	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 1                    # detects the car (physics layer 1)
	area.position = Vector2(x, surface_y - h / 2.0)

	var sprite := Sprite2D.new()
	sprite.texture = slime_tex
	sprite.scale = Vector2(SLIME_SCALE, SLIME_SCALE)
	area.add_child(sprite)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(w, h)
	shape.shape = rect
	area.add_child(shape)

	area.body_entered.connect(_on_slime_entered.bind(slime_lane))
	add_child(area)
	move_child(area, 3)                        # behind the car, in front of the roads
	slimes.append(area)


func _on_slime_entered(body: Node2D, slime_lane: int) -> void:
	if body != player or hit or slime_lane != lane:
		return
	hit = true
	_slime_hit.call_deferred()


func _slime_hit() -> void:
	if lane_tween and lane_tween.is_valid():
		lane_tween.kill()
	player.set("lane_changing", false)
	player.collision_mask = 1 << (lane + 1)
	player.set("cutscene", true)               # no more player control
	player.set("cutscene_throttle", player.get("throttle"))
	player.velocity.y = -SLIME_FLING

	# Points drain away on the way to heaven
	score_label.modulate = Color(1.0, 0.35, 0.35)
	create_tween().tween_method(_set_score, score, 0.0, HIT_FADE_DELAY + HIT_FADE_TIME)

	await get_tree().create_timer(HIT_FADE_DELAY).timeout
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, HIT_FADE_TIME)
	await tween.finished
	get_tree().change_scene_to_file(CUTSCENE_SCENE)


func _set_score(value: float) -> void:
	score = value
	score_label.text = "Points: %d" % int(score)
