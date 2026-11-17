class_name NameGen
extends RefCounted
## Procedural names for worlds and species. Same seed -> same names.

const _ONSETS := ["v", "k", "th", "m", "s", "d", "l", "b", "n", "g", "t", "z", "h", "r", "c", "f", "sk", "dr", "br", "gr"]
const _START := ["a", "e", "o", "i"]   ## some words start with a vowel
const _VOWELS := ["a", "e", "i", "o", "u", "a", "e", "o", "ae", "ia"]
const _CODAS := ["", "", "", "n", "r", "l", "th", "s", "x", "m", "nd", "rn"]
const _WORLD_SUFFIX := ["Isle", "Island", "Reach", "Atoll", "Key", "Holm", "Rock", "Haven"]

const _ADJ := ["Ashen", "Silver", "Hollow", "Whisper", "Ember", "Frost", "Gloam", "Sun", "Dusk",
	"Thorn", "Moss", "Pale", "Iron", "Amber", "Velvet", "Bitter", "Glimmer", "Shade", "Tall", "Crooked"]
const _ROOTS := {
	"pine": ["pine", "spire", "needle", "fir", "spruce"],
	"oak": ["oak", "crown", "bough", "elm", "canopy"],
	"birch": ["birch", "wand", "aspen", "willow", "bark"],
	"bush": ["shrub", "bramble", "brush", "thicket"],
	"berry": ["berry", "berrybush", "currant", "sloe"],
	"rock": ["stone", "boulder", "rock"],
	"ore": ["ore", "lode", "vein"],
	"grazer": ["hart", "strider", "grazer", "elk", "ram", "bok", "doe"],
	"defensive": ["boar", "tusker", "brute", "hog", "ox"],
	"critter": ["hopper", "vole", "skitter", "burrower", "kit"],
	"bird": ["finch", "lark", "swift", "warbler", "crow", "wing"],
}


static func syllable(rng: RandomNumberGenerator, last := false, first := false) -> String:
	if first and rng.randf() < 0.2:
		return _pick(rng, _START) + _pick(rng, _ONSETS) + _pick(rng, ["a", "e", "i", "o"])
	var s: String = _pick(rng, _ONSETS) + _pick(rng, _VOWELS)
	if last:
		s += _pick(rng, _CODAS)   # only the final syllable gets an ending consonant
	return s


## Pronounceable made-up word, e.g. "Velmora", "Thaskin".
static func word(rng: RandomNumberGenerator, min_syl := 2, max_syl := 3) -> String:
	var count := min_syl if rng.randf() < 0.65 else rng.randi_range(min_syl, max_syl)
	var w := ""
	for i in count:
		w += syllable(rng, i == count - 1, i == 0)
	if w.length() > 9:
		w = w.substr(0, 9)
	return w.capitalize()


static func world_name(seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return "%s %s" % [word(rng), _pick(rng, _WORLD_SUFFIX)]


## e.g. "Ember Spire", "Kaloth Bramble"
static func species_name(rng: RandomNumberGenerator, kind: String) -> String:
	var first: String = _pick(rng, _ADJ) if rng.randf() < 0.6 else word(rng, 2, 2)
	return "%s %s" % [first, String(_pick(rng, _ROOTS.get(kind, ["thing"]))).capitalize()]


static func _pick(rng: RandomNumberGenerator, arr: Array):
	return arr[rng.randi() % arr.size()]
