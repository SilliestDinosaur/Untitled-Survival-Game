class_name PlayerStats
extends Node
## Health, hunger, stamina and warmth. Pure numbers, no visuals, so it's easy to save and sync.

signal died
signal damaged(amount: float)

@export var max_health := 100.0
@export var max_hunger := 100.0
@export var max_stamina := 100.0
@export var max_warmth := 100.0
@export var hunger_drain := 100.0 / 900.0   ## Full to empty in ~15 minutes (a day is 16).
@export var starve_damage := 1.2            ## Health lost per second when starving.
@export var health_regen := 0.25            ## Per second while well fed.
@export var stamina_drain := 26.0           ## Per second while sprinting.
@export var stamina_regen := 14.0
@export var stamina_regen_delay := 1.2
@export var cold_rate := 0.4                ## Warmth lost per second per unit of cold.
@export var warm_up_rate := 2.0             ## Warmth regained per second when nothing is cold.
@export var freeze_damage := 0.7            ## Health lost per second at zero warmth.

var health: float
var hunger: float
var stamina: float
var warmth: float
## Last frame's exposure, for the HUD: cold (0..~3) and heat (0..) sources.
var cold := 0.0
var heat := 0.0
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
	warmth = max_warmth
	is_dead = false
	effects = {}


func tick(delta: float, sprinting: bool, cold_now := 0.0, heat_now := 0.0) -> void:
	if is_dead:
		return
	cold = cold_now
	heat = heat_now
	# Warmth: night, cold biomes and water drain it; fires and torches restore it.
	var net := heat_now - cold_now * cold_rate
	if cold_now <= 0.05 and net >= 0.0:
		net = maxf(net, warm_up_rate)
	warmth = clampf(warmth + net * delta, 0.0, max_warmth)
	if warmth <= 0.0:
		take_damage(freeze_damage * delta, false)
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
	elif hunger > max_hunger * 0.7 and warmth > max_warmth * 0.25 and health < max_health:
		health = minf(max_health, health + health_regen * delta)

	if sprinting:
		stamina = maxf(0.0, stamina - stamina_drain * delta)
		_regen_timer = stamina_regen_delay
	elif _regen_timer > 0.0:
		_regen_timer -= delta
	else:
		var regen := stamina_regen * (2.0 if effects.has("vigor") else 1.0) * (0.5 if is_cold() else 1.0)
		stamina = minf(max_stamina, stamina + regen * delta)


func take_damage(amount: float, notify := true) -> void:
	if is_dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	if notify:
		damaged.emit(amount)
	if health <= 0.0:
		is_dead = true
		died.emit()


## Chilled: stamina recovers slowly and health stops regenerating.
func is_cold() -> bool:
	return warmth < max_warmth * 0.25


func add_effect(id: String, seconds: float) -> void:
	effects[id] = maxf(effects.get(id, 0.0), seconds)


func eat(amount: float) -> void:
	hunger = minf(max_hunger, hunger + amount)
