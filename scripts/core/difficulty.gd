class_name Difficulty
extends RefCounted
## How hard survival is. Chosen when a world is created, and kept with its save. Normal is the
## baseline: hunger, cold and damage press harder than before, and resources give a little less.
## Easy eases all of that; Hard presses on.

const EASY := 0
const NORMAL := 1
const HARD := 2
const NAMES := ["Easy", "Normal", "Hard"]
const DESCRIPTIONS := [
	"Gentler hunger and cold, less damage. Resources come easily.",
	"Hunger, cold and danger press harder. Resources take real effort.",
	"Everything presses hard. Food and warmth have to be earned.",
]

## hunger / cold: how fast they drain. damage: what you take. regen: health recovery.
## yield: how much a resource gives per hit. ore: how much ore and crystal a deposit gives when it breaks.
## cache_metal: the chance a supply cache's tool is the world's first metal (the rest are stone).
const PRESETS := [
	{"hunger": 0.7, "cold": 0.7, "damage": 0.7, "regen": 1.3, "yield": 1.0, "ore": 1.3, "cache_metal": 0.25},
	{"hunger": 1.2, "cold": 1.25, "damage": 1.2, "regen": 1.0, "yield": 0.8, "ore": 1.0, "cache_metal": 0.1},
	{"hunger": 1.6, "cold": 1.6, "damage": 1.6, "regen": 0.7, "yield": 0.6, "ore": 0.75, "cache_metal": 0.0},
]


static func preset(level: int) -> Dictionary:
	return PRESETS[clampi(level, EASY, HARD)]
