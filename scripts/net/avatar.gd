class_name Avatar
extends RefCounted
## How a player looks to everyone else, and the models for it: a friendly floating figure (a rounded torso in their
## shirt colour, a head with a painted face), with the skin, hair style and colour, and hat or accessory they chose
## (see the Play with Friends screen). A look is a Dictionary of palette indices:
##   {shirt (Settings.PLAYER_COLORS), skin, hair, hair_color, hat}
## Used for the other players in a game (RemotePlayer) and the preview on the menu.

const SKINS := [Color(0.98, 0.86, 0.74), Color(0.96, 0.8, 0.66), Color(0.9, 0.7, 0.54), Color(0.86, 0.66, 0.5),
	Color(0.74, 0.54, 0.38), Color(0.68, 0.48, 0.34), Color(0.56, 0.38, 0.26), Color(0.42, 0.28, 0.2)]
const HAIR_COLORS := [Color(0.12, 0.09, 0.08), Color(0.24, 0.16, 0.11), Color(0.42, 0.27, 0.15), Color(0.56, 0.3, 0.14),
	Color(0.72, 0.38, 0.16), Color(0.86, 0.7, 0.42), Color(0.94, 0.88, 0.7), Color(0.62, 0.62, 0.64),
	Color(0.3, 0.46, 0.82), Color(0.86, 0.42, 0.62), Color(0.36, 0.66, 0.42), Color(0.56, 0.36, 0.78)]
const HAIR_STYLES := ["Short", "Long", "Ponytail", "Bun", "Spiky", "Mohawk", "Curly", "Bald"]
const HATS := ["None", "Straw hat", "Beanie", "Headband", "Bandana", "Flower", "Cap", "Feather"]


## A look made whole and safe: every index there and in range (it may come from the network or an old settings file).
static func clean(look: Variant, fallback_shirt := 0) -> Dictionary:
	var l: Dictionary = look if look is Dictionary else {}
	var pick := func(key: String, n: int, def: int) -> int: return posmod(int(l.get(key, def)), n)
	return {"shirt": pick.call("shirt", Settings.PLAYER_COLORS.size(), fallback_shirt), "skin": pick.call("skin", SKINS.size(), 1),
		"hair": pick.call("hair", HAIR_STYLES.size(), 0), "hair_color": pick.call("hair_color", HAIR_COLORS.size(), 1),
		"hat": pick.call("hat", HATS.size(), 0)}


## A random look (a fresh player's, or the Randomise button).
static func random(rng: RandomNumberGenerator) -> Dictionary:
	return {"shirt": rng.randi() % Settings.PLAYER_COLORS.size(), "skin": rng.randi() % SKINS.size(),
		"hair": rng.randi() % HAIR_STYLES.size(), "hair_color": rng.randi() % 8,   # (natural colours, mostly)
		"hat": 0 if rng.randf() < 0.5 else rng.randi() % HATS.size()}


## A rounded torso: wide shoulders tapering to the waist, with a collar and a belt line.
static func torso_mesh(color: Color, mat: Material) -> ArrayMesh:
	var k := MeshKit.new(7)
	var path := []
	var radii := []
	var profile := [0.17, 0.25, 0.28, 0.29, 0.3, 0.31, 0.3, 0.26, 0.16]
	for i in profile.size():
		var t := float(i) / (profile.size() - 1)
		path.append(Vector3(0, 0.55 + t * 0.8, 0))
		radii.append(profile[i])
	var dark := color.darkened(0.25)
	var light := color.lightened(0.12)
	var shirt := func(t: float, a: float) -> Color:
		if t < 0.13:
			return dark            # belt / hem
		if t > 0.88:
			return light           # collar
		return color.lightened(0.05) if a > PI * 0.6 and a < PI * 1.4 else color
	var oval := func(_t: float, _a: float) -> Vector2: return Vector2(1.0, 0.72)
	k.loft(path, radii, 20, color, shirt, oval, true, true)
	return k.commit(mat)


## The head (its middle at the origin, facing -z): skin, painted eyes and a smile, hair in its style, and the hat.
static func head_mesh(look: Dictionary, mat: Material) -> ArrayMesh:
	var l := clean(look)
	var skin: Color = SKINS[l.skin]
	var hair: Color = HAIR_COLORS[l.hair_color]
	var shirt: Color = Settings.PLAYER_COLORS[l.shirt]
	var k := MeshKit.new(9)
	k.add_primitive(MeshKit.sphere(0.26, 22, 16), Transform3D(Basis.from_scale(Vector3(1.0, 1.06, 0.98)), Vector3.ZERO), skin, 0.0, 0.03)
	var eye := Color(0.12, 0.09, 0.08)
	for side in [-1.0, 1.0]:
		k.add_primitive(MeshKit.sphere(0.042, 10, 7), Transform3D(Basis.from_scale(Vector3(0.8, 1.25, 0.5)), Vector3(side * 0.09, 0.04, -0.243)), eye, 0.0, 0.0)
		k.add_primitive(MeshKit.sphere(0.013, 6, 4), Transform3D(Basis(), Vector3(side * 0.09 + 0.012, 0.065, -0.262)), Color(1, 1, 1), 0.0, 0.0)
	var smile := []
	var sr := []
	for i in 7:
		var t := (i / 6.0 - 0.5) * 1.4
		smile.append(Vector3(sin(t) * 0.085, -0.075 - cos(t) * 0.025 + 0.025, -0.247 + absf(t) * 0.015))
		sr.append(0.011)
	k.loft(smile, sr, 6, eye.lightened(0.15), Callable(), Callable(), true, true)
	# Under a hat that covers the crown, tall hair is tucked away (long hair and a ponytail still show below it).
	var style := int(l.hair)
	if HATS[l.hat] in ["Beanie", "Cap", "Bandana", "Straw hat"] and HAIR_STYLES[style] in ["Spiky", "Mohawk", "Curly", "Bun"]:
		style = HAIR_STYLES.find("Short")
	_hair(k, style, hair)
	_hat(k, int(l.hat), shirt, hair)
	return k.commit(mat)


static func _hair(k: MeshKit, style: int, hair: Color) -> void:
	var cap := func(scale: Vector3, at: Vector3) -> void:
		k.add_primitive(MeshKit.sphere(0.265, 16, 10), Transform3D(Basis.from_scale(scale), at), hair, 0.03, 0.05)
	match HAIR_STYLES[style]:
		"Short":
			cap.call(Vector3(1.03, 0.6, 1.0), Vector3(0, 0.125, 0.025))
		"Long":   # a cap, and hair falling to the shoulders behind and at the sides
			cap.call(Vector3(1.05, 0.62, 1.02), Vector3(0, 0.12, 0.03))
			k.add_primitive(MeshKit.sphere(0.25, 14, 10), Transform3D(Basis.from_scale(Vector3(1.04, 1.25, 0.6)), Vector3(0, -0.06, 0.14)), hair, 0.02, 0.05)
			for side in [-1.0, 1.0]:
				k.add_primitive(MeshKit.sphere(0.1, 10, 8), Transform3D(Basis.from_scale(Vector3(0.6, 1.8, 0.9)), Vector3(side * 0.24, -0.08, 0.02)), hair, 0.02, 0.05)
		"Ponytail":
			cap.call(Vector3(1.03, 0.6, 1.0), Vector3(0, 0.125, 0.025))
			k.loft([Vector3(0, 0.12, 0.25), Vector3(0, 0.02, 0.34), Vector3(0, -0.16, 0.36), Vector3(0, -0.3, 0.32)], [0.07, 0.075, 0.06, 0.03], 10, hair)
			k.add_primitive(MeshKit.cylinder(0.05, 0.05, 0.04, 10), Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(0, 0.1, 0.27)), hair.darkened(0.4), 0.0, 0.0)
		"Bun":
			cap.call(Vector3(1.03, 0.6, 1.0), Vector3(0, 0.125, 0.025))
			k.add_primitive(MeshKit.sphere(0.11, 12, 9), Transform3D(Basis(), Vector3(0, 0.24, 0.16)), hair, 0.03, 0.05)
		"Spiky":
			cap.call(Vector3(1.01, 0.55, 0.99), Vector3(0, 0.13, 0.02))
			for i in 9:
				var a := TAU * i / 9.0
				var root := Vector3(cos(a) * 0.14, 0.2, sin(a) * 0.14 + 0.02)
				k.loft([root, root + Vector3(cos(a) * 0.08, 0.13, sin(a) * 0.08)], [0.045, 0.005], 6, hair)
		"Mohawk":
			for i in 7:
				var z := lerpf(-0.18, 0.22, i / 6.0)
				var y := 0.2 + 0.07 * sin(lerpf(0.3, 2.8, i / 6.0))
				k.add_primitive(MeshKit.sphere(0.07, 8, 6), Transform3D(Basis.from_scale(Vector3(0.6, 1.6, 1.0)), Vector3(0, y + 0.05, z)), hair, 0.02, 0.05)
		"Curly":
			for i in 14:
				var a := TAU * i / 14.0
				var r := 0.2 if i % 2 == 0 else 0.15
				k.add_primitive(MeshKit.sphere(0.09, 9, 7), Transform3D(Basis(), Vector3(cos(a) * r, 0.17 + 0.04 * (i % 3), sin(a) * r + 0.05)), hair, 0.02, 0.06)
			k.add_primitive(MeshKit.sphere(0.1, 9, 7), Transform3D(Basis(), Vector3(0, 0.25, 0.04)), hair, 0.02, 0.06)
		_:   # Bald
			pass


static func _hat(k: MeshKit, hat: int, shirt: Color, hair: Color) -> void:
	match HATS[hat]:
		"Straw hat":
			var straw := Color(0.86, 0.74, 0.46)
			k.add_primitive(MeshKit.cylinder(0.42, 0.44, 0.03, 20), Transform3D(Basis(), Vector3(0, 0.17, 0.02)), straw, 0.0, 0.06)
			k.add_primitive(MeshKit.cylinder(0.2, 0.25, 0.17, 16), Transform3D(Basis(), Vector3(0, 0.27, 0.02)), straw, 0.0, 0.06)
			k.add_primitive(MeshKit.cylinder(0.252, 0.252, 0.05, 16), Transform3D(Basis(), Vector3(0, 0.215, 0.02)), shirt.darkened(0.2), 0.0, 0.0)
		"Beanie":
			k.add_primitive(MeshKit.sphere(0.275, 16, 10), Transform3D(Basis.from_scale(Vector3(1.02, 0.72, 1.0)), Vector3(0, 0.12, 0.02)), shirt, 0.0, 0.04)
			k.add_primitive(MeshKit.cylinder(0.275, 0.275, 0.07, 16), Transform3D(Basis(), Vector3(0, 0.1, 0.02)), shirt.darkened(0.15), 0.0, 0.0)
			k.add_primitive(MeshKit.sphere(0.065, 8, 6), Transform3D(Basis(), Vector3(0, 0.33, 0.02)), shirt.lightened(0.3), 0.04, 0.0)
		"Headband":
			k.add_primitive(MeshKit.cylinder(0.27, 0.27, 0.06, 18), Transform3D(Basis(Vector3.RIGHT, -0.15), Vector3(0, 0.1, 0.01)), shirt.lightened(0.1), 0.0, 0.0)
		"Bandana":
			k.add_primitive(MeshKit.sphere(0.27, 14, 9), Transform3D(Basis.from_scale(Vector3(1.03, 0.62, 1.0)), Vector3(0, 0.13, 0.03)), shirt.darkened(0.1), 0.0, 0.05)
			for side in [-1.0, 1.0]:
				k.loft([Vector3(side * 0.03, 0.06, 0.26), Vector3(side * 0.1, -0.06, 0.33)], [0.035, 0.015], 6, shirt.darkened(0.1))
		"Flower":
			var petal := Color(0.98, 0.9, 0.95) if hair.v < 0.6 else Color(0.95, 0.45, 0.55)
			for i in 5:
				var a := TAU * i / 5.0
				k.add_primitive(MeshKit.sphere(0.045, 8, 6), Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 1.0)), Vector3(0.2 + cos(a) * 0.045, 0.17, -0.06 + sin(a) * 0.045)), petal, 0.0, 0.0)
			k.add_primitive(MeshKit.sphere(0.03, 8, 6), Transform3D(Basis(), Vector3(0.2, 0.185, -0.06)), Color(0.96, 0.78, 0.26), 0.0, 0.0)
		"Cap":
			k.add_primitive(MeshKit.sphere(0.272, 16, 10), Transform3D(Basis.from_scale(Vector3(1.02, 0.62, 1.0)), Vector3(0, 0.13, 0.02)), shirt, 0.0, 0.04)
			k.add_primitive(MeshKit.cylinder(0.17, 0.17, 0.025, 16), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.75)), Vector3(0, 0.12, -0.27)), shirt.darkened(0.2), 0.0, 0.0)
		"Feather":
			k.add_primitive(MeshKit.cylinder(0.27, 0.27, 0.05, 18), Transform3D(Basis(), Vector3(0, 0.1, 0.02)), Color(0.42, 0.28, 0.18), 0.0, 0.0)
			k.loft([Vector3(0.22, 0.1, 0.14), Vector3(0.27, 0.3, 0.2), Vector3(0.24, 0.48, 0.27)], [0.035, 0.04, 0.008], 6, shirt.lightened(0.25))
		_:
			pass
