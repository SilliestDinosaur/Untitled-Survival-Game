class_name PlayerStats
extends Node
## Health, hunger and stamina. Pure numbers, no visuals, so it's easy to save and sync.

signal died
signal damaged(amount: float)

@export var max_health := 100.0
@export var max_hunger := 100.0
@export var max_stamina := 100.0
@export var hunger_drain := 100.0 / 1500.0  ## Full to empty in ~25 minutes.
@export var starve_damage := 1.0            ## Health lost per second when starving.
@export var health_regen := 0.4             ## Per second while well fed.
@export var stamina_drain := 20.0           ## Per second while sprinting.
@export var stamina_regen := 18.0
@export var stamina_regen_delay := 0.9

var health: float
var hunger: float
var stamina: float
var is_dead := false
## Active status effects: id -> seconds left (see ItemDB.EFFECTS).
var effects := {}
var _regen_timer := 0.0


func _ready() -> void:
	reset()


func reset() -> void:
	health = max_health
	hunger = max_hunger
	stamina = max_stamina
	is_dead = false
	effects = {}


func tick(delta: float, sprinting: bool) -> void:
	if is_dead:
		return
	for e: String in effects.keys():
		effects[e] -= delta
		if effects[e] <= 0.0:
			effects.erase(e)
	if effects.has("mend"):
		health = minf(max_health, health + 2.5 * delta)
	if effects.has("poison"):
		take_damage(1.6 * delta, false)
	var drain := hunger_drain * (1.6 if sprinting else 1.0) * (0.35 if effects.has("satiate") else 1.0)
	hunger = maxf(0.0, hunger - drain * delta)
	if hunger <= 0.0:
		take_damage(starve_damage * delta, false)
	elif hunger > max_hunger * 0.6 and health < max_health:
		health = minf(max_health, health + health_regen * delta)

	if sprinting:
		stamina = maxf(0.0, stamina - stamina_drain * delta)
		_regen_timer = stamina_regen_delay
	elif _regen_timer > 0.0:
		_regen_timer -= delta
	else:
		stamina = minf(max_stamina, stamina + stamina_regen * delta * (2.0 if effects.has("vigor") else 1.0))


func take_damage(amount: float, notify := true) -> void:
	if is_dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	if notify:
		damaged.emit(amount)
	if health <= 0.0:
		is_dead = true
		died.emit()


func add_effect(id: String, seconds: float) -> void:
	effects[id] = maxf(effects.get(id, 0.0), seconds)


func eat(amount: float) -> void:
	hunger = minf(max_hunger, hunger + amount)
