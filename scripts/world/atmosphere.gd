extends Node
## Sun, moon, sky, fog and graphics settings, driven by the day/night cycle (Game.time_of_day).
## World colors come from the palette; dusk warms them, night cools and darkens them.

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var environment: Environment
var sky_material: ShaderMaterial

const NIGHT_TOP := Color(0.02, 0.03, 0.08)
const NIGHT_HORIZON := Color(0.08, 0.1, 0.2)
const DUSK_TOP := Color(0.32, 0.3, 0.55)
const DUSK_HORIZON := Color(0.98, 0.62, 0.42)
const DUSK_GLOW := Color(1.0, 0.55, 0.3)
## How much of the sky's light reaches the ground as ambient, by day and on a moonless-dark night. (The ambient
## comes from the sky itself, so this share is the dimmer: Environment.ambient_light_energy only scales the flat
## ambient colour, which is black above ground.)
const SKY_AMBIENT_DAY := 0.85
const SKY_AMBIENT_NIGHT := 0.3

var _day_top: Color
var _day_horizon: Color
var _day_sun: Color
var _update_cd := 0.0
## (Caves aren't darkened here: the world's light stays the same everywhere, and cave walls and the things in caves
## see less of the sky by their own shading, see Caves.sky_seen and CaveShade.)


func _ready() -> void:
	add_child(AmbientFx.new())   # fireflies, falling leaves, snow, blowing dust
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.shadow_blur = 2.5
	sun.shadow_opacity = 0.85
	sun.directional_shadow_fade_start = 0.75
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.shadow_enabled = true
	moon.shadow_opacity = 0.6
	moon.shadow_blur = 3.0
	add_child(moon)

	sky_material = ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/sky.gdshader")
	sky_material.set_shader_parameter("cloud_noise", _cloud_texture())
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_REALTIME   # cheap updates; needed for clouds and day/night
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = SKY_AMBIENT_DAY
	environment.ambient_light_color = Color.BLACK
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
	environment.glow_intensity = 0.35
	environment.glow_bloom = 0.05

	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	Game.world_changed.connect(apply_palette)
	Settings.changed.connect(apply_settings)
	apply_palette()
	apply_settings()


func apply_palette() -> void:
	var pal: WorldPalette = Game.palette
	_day_top = pal.sky_top
	_day_horizon = pal.sky_horizon
	_day_sun = pal.sun
	sky_material.set_shader_parameter("ground_color", pal.water_deep.lerp(pal.sky_horizon, 0.4))
	sky_material.set_shader_parameter("cloud_color", pal.cloud)
	var rng := RandomNumberGenerator.new()
	rng.seed = Game.world_seed + 99
	sky_material.set_shader_parameter("cloud_coverage", rng.randf_range(0.3, 0.6))
	_apply_time(true)


func _process(delta: float) -> void:
	_update_cd -= delta
	if _update_cd <= 0.0:
		_update_cd = 0.05   # 20 times a second is plenty for a slow sun
		_apply_time()


## 0..1 values describing the light right now.
func light_state(t: float) -> Dictionary:
	# Sun elevation: -1 at midnight, +1 at noon, 0 at Game.SUNRISE / Game.SUNSET.
	var elev := sin(Game.sun_angle(t))
	var day := smoothstep(-0.12, 0.12, elev)            # 0 night .. 1 day
	var golden := (1.0 - smoothstep(0.08, 0.45, absf(elev))) * smoothstep(-0.2, 0.0, elev)
	return {"elev": elev, "day": day, "night": 1.0 - day, "golden": golden}


func _apply_time(_force := false) -> void:
	var t := Game.time_of_day
	var st := light_state(t)
	var day: float = st.day
	var golden: float = st.golden
	# Sun travels east -> west through the south; the moon is opposite.
	var ang := Game.sun_angle(t)
	var sun_dir := Vector3(cos(ang) * 0.85, sin(ang), 0.35).normalized()
	var moon_dir := -sun_dir + Vector3(0, 0.25, 0)
	moon_dir = moon_dir.normalized()
	_point(sun, sun_dir)
	_point(moon, moon_dir)
	sun.light_energy = 1.25 * smoothstep(-0.05, 0.15, sun_dir.y)
	sun.light_color = _day_sun.lerp(DUSK_GLOW, golden * 0.85)
	sun.visible = sun_dir.y > -0.08
	moon.light_energy = 0.13 * smoothstep(0.0, 0.2, moon_dir.y) * (1.0 - day)
	moon.visible = moon.light_energy > 0.01 and Settings.shadow_quality != "Off"
	moon.shadow_enabled = Settings.shadow_quality in ["High", "Ultra"]

	var top := NIGHT_TOP.lerp(_day_top, day).lerp(DUSK_TOP, golden * 0.5)
	var horizon := NIGHT_HORIZON.lerp(_day_horizon, day).lerp(DUSK_HORIZON, golden * 0.7)
	sky_material.set_shader_parameter("top_color", top)
	sky_material.set_shader_parameter("horizon_color", horizon)
	sky_material.set_shader_parameter("sun_glow", DUSK_GLOW)
	sky_material.set_shader_parameter("night", 1.0 - day)
	sky_material.set_shader_parameter("sunset", golden)
	sky_material.set_shader_parameter("sun_dir", sun_dir)
	sky_material.set_shader_parameter("moon_dir", moon_dir)
	environment.fog_light_color = horizon.lerp(top, 0.3 * (1.0 - day))
	environment.ambient_light_sky_contribution = lerpf(SKY_AMBIENT_NIGHT, SKY_AMBIENT_DAY, day)
	environment.fog_sun_scatter = 0.35 + golden * 0.4
	environment.adjustment_saturation = lerpf(0.55, 1.1, day)
	var water := get_tree().get_first_node_in_group("water") as MeshInstance3D
	if water and water.mesh:
		var wm := (water.mesh as PlaneMesh).material as ShaderMaterial
		wm.set_shader_parameter("sky_color", horizon.lerp(top, 0.35))
		wm.set_shader_parameter("night", 1.0 - day)


func _point(light: DirectionalLight3D, toward: Vector3) -> void:
	# A directional light shines along its -Z axis, so aim -Z away from the light's position.
	var up := Vector3.UP if absf(toward.y) < 0.99 else Vector3.FORWARD
	light.basis = Basis.looking_at(-toward, up)


func apply_settings() -> void:
	var dist := Settings.view_radius() * Game.CHUNK_SIZE
	environment.fog_depth_begin = dist * 0.42   # strong aerial perspective = painted depth
	environment.fog_depth_end = dist * 0.95

	var viewport := get_viewport()
	# Shadows
	match Settings.shadow_quality:
		"Off":
			sun.shadow_enabled = false
		"Low":
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 50.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			RenderingServer.directional_shadow_atlas_set_size(2048, false)
		"Medium":
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 100.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
		"High":
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 160.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
		_:
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 240.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			RenderingServer.directional_shadow_atlas_set_size(8192, true)
	moon.directional_shadow_max_distance = minf(sun.directional_shadow_max_distance, 80.0)
	# Anti-aliasing
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	match Settings.anti_aliasing:
		"FXAA": viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		"MSAA 2x": viewport.msaa_3d = Viewport.MSAA_2X
		"MSAA 4x": viewport.msaa_3d = Viewport.MSAA_4X
		"MSAA 8x": viewport.msaa_3d = Viewport.MSAA_8X
		"TAA": viewport.use_taa = true
	# Resolution scale (FSR upscaling below 100%)
	viewport.scaling_3d_scale = Settings.render_scale
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if Settings.render_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	environment.ssao_enabled = Settings.ambient_occlusion
	environment.glow_enabled = Settings.glow
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if Settings.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = Settings.fps_cap


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
