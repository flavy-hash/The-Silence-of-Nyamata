extends "res://scripts/world/interactable.gd"
## A villager you can talk to.
##
## Which conversation plays is data-driven: `conversations` is an ordered list of
## {"conversation": id, "if": [conditions]} taken from the chapter JSON; the first
## entry whose conditions pass is used. `barks` are short ambient lines said when
## the player walks past.

const CharacterModel := preload("res://scripts/world/character_model.gd")

@export var npc_id := ""
@export var display_name := ""

var conversations: Array = []
var barks: Array = []
var model: Node3D

var _body: StaticBody3D
var _bark_cooldown := 0.0
var _bark_index := 0
var _walk_tween: Tween
var _idle_yaw := 0.0


## Configure appearance before adding to the tree. `look` keys mirror CharacterModel exports.
func setup(id: String, name_text: String, look: Dictionary) -> void:
	npc_id = id
	display_name = name_text
	marker_id = id
	model = CharacterModel.new()
	for k in look:
		model.set(k, look[k])


func _ready() -> void:
	super()
	prompt = "Talk to %s" % display_name
	interact_radius = 2.4
	if model == null:
		model = CharacterModel.new()
	add_child(model)
	_body = StaticBody3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.7
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.85
	_body.add_child(col)
	add_child(_body)
	_idle_yaw = model.rotation.y
	_bark_cooldown = randf_range(2.0, 8.0)


func resolve_conversation() -> String:
	for rule in conversations:
		if GameState.check(rule.get("if")):
			return rule["conversation"]
	return ""


func is_interactable(by: Node) -> bool:
	return super(by) and resolve_conversation() != ""


func get_interact_position() -> Vector3:
	return global_position


func interact(by: Node) -> void:
	var conv := resolve_conversation()
	if conv == "":
		return
	face(by.global_position)
	if by.has_method("face_towards"):
		by.face_towards(global_position)
	DialogueManager.start(conv)
	used.emit(by)


func face(pos: Vector3) -> void:
	var to := pos - global_position
	if Vector2(to.x, to.z).length() > 0.01:
		model.rotation.y = atan2(to.x, to.z)


func set_facing(yaw: float) -> void:
	_idle_yaw = yaw
	model.rotation.y = yaw


## Walks in a straight line along the terrain (no pathfinding; for short scripted moves).
func walk_to(target: Vector3, speed := 1.6, height_func := Callable()) -> void:
	if _walk_tween:
		_walk_tween.kill()
	var start := global_position
	var dist := Vector2(target.x - start.x, target.z - start.z).length()
	face(target)
	model.set_motion(speed)
	_walk_tween = create_tween()
	_walk_tween.tween_method(func(t: float):
		var p := start.lerp(target, t)
		if height_func.is_valid():
			p.y = height_func.call(p.x, p.z)
		global_position = p
	, 0.0, 1.0, max(dist / speed, 0.1))
	await _walk_tween.finished
	model.set_motion(0.0)


func _process(delta: float) -> void:
	if barks.is_empty() or DialogueManager.is_active():
		return
	_bark_cooldown -= delta
	if _bark_cooldown > 0.0:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player and player.global_position.distance_to(global_position) < 6.0 and not GameState.is_locked():
		var b: Dictionary = barks[_bark_index % barks.size()]
		if GameState.check(b.get("if")):
			UI.bark(display_name, b["text"])
			_bark_index += 1
			_bark_cooldown = 30.0
			return
		_bark_index += 1
	_bark_cooldown = 1.0
