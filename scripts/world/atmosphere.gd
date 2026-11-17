extends Node
## Sun, sky, fog and graphics quality. Colors come from the world's palette.
## (This is where the day/night cycle will live.)

var sun: DirectionalLight3D
var environment: Environment
var sky_material: ShaderMaterial
var _post: ColorRect


func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.shadow_blur = 2.5
	sun.shadow_opacity = 0.85
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_fade_start = 0.75
	add_child(sun)

	sky_material = ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/sky.gdshader")
	sky_material.set_shader_parameter("cloud_noise", _cloud_texture())
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_REALTIME   # cheap updates; needed for moving clouds/day-night
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.85
	environment.ambient_light_energy = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 6.0
	# Depth fog hides chunks streaming in at the edge of the view distance.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_density = 1.0
	environment.fog_sun_scatter = 0.35
	environment.fog_sky_affect = 0.0
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.1
	environment.adjustment_contrast = 0.98
	environment.ssao_radius = 1.5
	environment.ssao_intensity = 1.6

	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	# Painterly screen filter. Layer -1 draws over the 3D world but under the HUD.
	var post_layer := CanvasLayer.new()
	post_layer.layer = -1
	add_child(post_layer)
	_post = ColorRect.new()
	_post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post.material = ArtStyle.material(preload("res://shaders/paint_post.gdshader"))
	(_post.material as ShaderMaterial).set_shader_parameter("paper", ArtStyle.paper_texture())
	post_layer.add_child(_post)

	Game.world_changed.connect(apply_palette)
	Settings.changed.connect(apply_settings)
	apply_palette()
	apply_settings()


func apply_palette() -> void:
	var pal: WorldPalette = Game.palette
	sun.light_color = pal.sun
	sky_material.set_shader_parameter("top_color", pal.sky_top)
	sky_material.set_shader_parameter("horizon_color", pal.sky_horizon)
	sky_material.set_shader_parameter("ground_color", pal.water_deep.lerp(pal.sky_horizon, 0.4))
	sky_material.set_shader_parameter("cloud_color", pal.cloud)
	var rng := RandomNumberGenerator.new()
	rng.seed = Game.world_seed + 99
	sky_material.set_shader_parameter("cloud_coverage", rng.randf_range(0.3, 0.6))
	environment.fog_light_color = pal.sky_horizon


func apply_settings() -> void:
	var dist := Settings.view_radius() * Game.CHUNK_SIZE
	environment.fog_depth_begin = dist * 0.42   # strong aerial perspective = painted depth
	environment.fog_depth_end = dist * 0.95

	var q := Settings.quality
	var viewport := get_viewport()
	match q:
		"Low":
			sun.directional_shadow_max_distance = 60.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			environment.glow_enabled = false
			environment.ssao_enabled = false
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			_set_paint_radius(0)
		"Medium":
			sun.directional_shadow_max_distance = 110.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			environment.glow_enabled = true
			environment.ssao_enabled = false
			viewport.msaa_3d = Viewport.MSAA_2X
			_set_paint_radius(3)
		_:
			sun.directional_shadow_max_distance = 160.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			environment.glow_enabled = true
			environment.ssao_enabled = true
			viewport.msaa_3d = Viewport.MSAA_4X
			_set_paint_radius(4)
	environment.glow_intensity = 0.35
	environment.glow_bloom = 0.05


func _set_paint_radius(r: int) -> void:
	(_post.material as ShaderMaterial).set_shader_parameter("radius", r)


func _cloud_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.006
	noise.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	return tex
