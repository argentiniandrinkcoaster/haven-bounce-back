extends Node

const TILE_PATH := "res://art/highway-block.png"   # your PNG
const GROUND_Y := 400.0                   # y of the top surface of the ground
const GROUND_SCALE := 1.3                 # scale of the ground image
const STRIP_TILES := 40                   # keep this even
const SPAWN_HEIGHT := 150.0               # how far above the ground the player starts
const HITBOX_OFFSET := 220.0   # px to move the ground hitbox down (negative = up)

@onready var player: CharacterBody2D = $CharacterBody2D

var ground: StaticBody2D
var tile_w: float


func _ready() -> void:
	var tex := load(TILE_PATH) as Texture2D
	tile_w = tex.get_width() * GROUND_SCALE
	var tile_h := tex.get_height() * GROUND_SCALE
	var strip_w := tile_w * STRIP_TILES

	ground = StaticBody2D.new()
	add_child(ground)
	move_child(ground, 0)  # draws behind the player
	ground.position = Vector2(0, GROUND_Y + tile_h / 2.0)

	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, tex.get_width() * STRIP_TILES, tex.get_height())
	sprite.scale = Vector2(GROUND_SCALE, GROUND_SCALE)
	ground.add_child(sprite)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(strip_w, tile_h)
	shape.shape = rect
	shape.shape = rect
	shape.position.y = HITBOX_OFFSET
	ground.add_child(shape)

	player.position = Vector2(0, GROUND_Y - SPAWN_HEIGHT)

func _physics_process(_delta: float) -> void:
	ground.position.x = snappedf(player.position.x, tile_w)
