class_name ArtStyle
extends RefCounted
## Shared look for the painterly/gouache style: brush + paper textures and material helpers.

const PAINTED_SHADER := preload("res://shaders/painted.gdshader")

static var _brush: NoiseTexture2D
static var _paper: NoiseTexture2D
static var _strokes: ImageTexture


## Soft noise used for brush-stroke color variation on every painted surface.
static func brush_texture() -> NoiseTexture2D:
	if not _brush:
		var noise := FastNoiseLite.new()
		noise.seed = 7
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.012
		noise.fractal_octaves = 4
		noise.fractal_gain = 0.55
		_brush = NoiseTexture2D.new()
		_brush.width = 512
		_brush.height = 512
		_brush.seamless = true
		_brush.generate_mipmaps = true
		_brush.noise = noise
	return _brush


## A tileable texture of thousands of short, overlapping brush daubs at varying angles
## and values. Materials sample it to make every surface look hand-painted.
static func stroke_texture() -> ImageTexture:
	if _strokes:
		return _strokes
	const N := 256
	var img := Image.create(N, N, false, Image.FORMAT_L8)
	var buf := PackedFloat32Array()
	buf.resize(N * N)
	buf.fill(0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	# Strokes lean mostly one way (like a painter's hand) with some variation.
	for i in 1400:
		var cx := rng.randf() * N
		var cy := rng.randf() * N
		var ang := rng.randf_range(-0.5, 0.5) + (PI * 0.5 if rng.randf() < 0.25 else 0.0)
		var length := rng.randf_range(6.0, 16.0)
		var width := rng.randf_range(1.6, 3.6)
		var value := clampf(rng.randfn(0.5, 0.2), 0.0, 1.0)
		var opacity := rng.randf_range(0.35, 0.8)
		var dx := cos(ang)
		var dy := sin(ang)
		var r := int(length + width) + 1
		for oy in range(-r, r + 1):
			for ox in range(-r, r + 1):
				# Distance along / across the stroke.
				var along := ox * dx + oy * dy
				var across := -ox * dy + oy * dx
				var t := absf(along) / length
				if t > 1.0:
					continue
				var w := width * (1.0 - t * t * 0.6)   # tapered ends
				var a := 1.0 - smoothstep(w * 0.6, w, absf(across))
				if a <= 0.0:
					continue
				a *= opacity * (1.0 - smoothstep(0.7, 1.0, t))
				var px := posmod(int(cx) + ox, N)
				var py := posmod(int(cy) + oy, N)
				var k := py * N + px
				buf[k] = lerpf(buf[k], value, a)
	for y in N:
		for x in N:
			img.set_pixel(x, y, Color(buf[y * N + x], 0, 0))
	img.generate_mipmaps()
	_strokes = ImageTexture.create_from_image(img)
	return _strokes


## Fine grain for painted paper (UI).
static func paper_texture() -> NoiseTexture2D:
	if not _paper:
		var noise := FastNoiseLite.new()
		noise.seed = 3
		noise.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
		noise.frequency = 0.09
		noise.fractal_octaves = 3
		_paper = NoiseTexture2D.new()
		_paper.width = 512
		_paper.height = 512
		_paper.seamless = true
		_paper.generate_mipmaps = true
		_paper.noise = noise
	return _paper


## A ShaderMaterial for one of the painterly shaders, with the brush texture wired in.
static func material(shader: Shader, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("brush_noise", brush_texture())
	m.set_shader_parameter("stroke_tex", stroke_texture())
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	return m


static func painted(params := {}) -> ShaderMaterial:
	return material(PAINTED_SHADER, params)
