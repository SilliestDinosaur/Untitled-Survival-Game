class_name ArtStyle
extends RefCounted
## Shared look for the painterly/gouache style: brush + paper textures and material helpers.

const PAINTED_SHADER := preload("res://shaders/painted.gdshader")

static var _brush: NoiseTexture2D
static var _paper: NoiseTexture2D


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


## Fine grain for the paper overlay in the screen filter.
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
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	return m


static func painted(params := {}) -> ShaderMaterial:
	return material(PAINTED_SHADER, params)
