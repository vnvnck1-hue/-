class_name Mats
extends RefCounted
## Material & procedural texture helpers. Soft-shaded toy look: low specular, rim light, no outlines.

static var _cache := {}
static var _tex := {}

## Shared, lit material for props (cached per color).
static func prop(color: Color, rough := 0.85) -> StandardMaterial3D:
	var key := "p%s%.2f" % [color.to_html(), rough]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic_specular = 0.25
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.6
	_cache[key] = m
	return m

## Unique material for characters (needs per-instance flash / ghost fade).
static func toy(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	m.metallic_specular = 0.3
	m.rim_enabled = true
	m.rim = 0.3
	m.rim_tint = 0.7
	m.emission_enabled = true
	m.emission = Color(0, 0, 0)
	return m

static func glow(color: Color, energy := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, color.a)
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

## Unshaded transparent material for mesh-based VFX (alpha tweened by caller).
static func fx(color: Color, additive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

## Soft-lit puff material (clouds of smoke look volumetric-ish but cartoony).
static func puff(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.rim_enabled = true
	m.rim = 0.6
	m.emission_enabled = true
	m.emission = color * 0.35
	return m

## Billboard particle material using a procedural sprite.
static func particle(shape: String, additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = texture(shape)
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

## Billboard quad material (non particle).
static func sprite(shape: String, color: Color, additive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = texture(shape)
	m.albedo_color = color
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

## Flat ground decal-like quad material.
static func ground(shape: String, color: Color, additive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = texture(shape)
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

static func texture(shape: String) -> Texture2D:
	if _tex.has(shape):
		return _tex[shape]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var p := (Vector2(x, y) + Vector2(0.5, 0.5) - c) / (size * 0.5)
			var d := p.length()
			var a := 0.0
			match shape:
				"soft":
					a = clampf(1.0 - d, 0.0, 1.0)
					a = a * a
				"circle":
					a = clampf((1.0 - d) * 18.0, 0.0, 1.0)
				"blob":
					a = clampf(1.0 - d, 0.0, 1.0)
					a = smoothstep(0.0, 0.7, a)
				"ring":
					a = clampf(1.0 - absf(d - 0.8) * 9.0, 0.0, 1.0)
				"ring_soft":
					a = clampf(1.0 - absf(d - 0.78) * 5.0, 0.0, 1.0)
					a *= clampf((1.0 - d) * 12.0, 0.0, 1.0)
				"star":
					var ang := atan2(p.y, p.x)
					var r := 0.42 + 0.5 * pow(absf(cos(ang * 2.0)), 6.0)
					a = clampf((r - d) * 14.0, 0.0, 1.0)
					a = maxf(a, clampf(1.0 - d * 2.6, 0.0, 1.0))
				"star5":
					var ang2 := atan2(p.y, p.x) + PI * 0.5
					var k := fmod(absf(ang2), TAU / 5.0) - TAU / 10.0
					var r2 := 0.95 * cos(TAU / 10.0) / cos(k) * (0.55 + 0.45 * absf(cos(k * 2.5)))
					a = clampf((r2 * 0.95 - d) * 14.0, 0.0, 1.0)
				"square":
					a = 1.0 if (absf(p.x) < 0.8 and absf(p.y) < 0.8) else 0.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[shape] = t
	return t
