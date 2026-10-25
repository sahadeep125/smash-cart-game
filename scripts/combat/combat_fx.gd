## Procedural visual helpers (materials, particle bursts, smoke trails).
## Uses CPUParticles3D only (gl_compatibility renderer).
class_name CombatFx
extends RefCounted

static var _headless: int = -1
static var _meshes: Dictionary = {}


## Meshes are shared and kept alive here: cheaper, and freeing a node together with its
## unique mesh spams errors on the headless dummy renderer.
static func shared_mesh(key: String, maker: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = maker.call()
	return _meshes[key]


static func shared_box(size: Vector3) -> Mesh:
	return shared_mesh("box%s" % size, func():
		var b := BoxMesh.new()
		b.size = size
		return b)


static func shared_sphere(radius: float, segments := 8, rings := 4) -> Mesh:
	return shared_mesh("sph%s_%d_%d" % [radius, segments, rings], func(): return low_poly_sphere(radius, segments, rings))


static func shared_cylinder(top: float, bottom: float, height: float, segments := 6) -> Mesh:
	return shared_mesh("cyl%s_%s_%s_%d" % [top, bottom, height, segments], func():
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = height
		c.radial_segments = segments
		return c)


## False on the headless dummy renderer, where particle meshes only produce errors.
static func particles_visible() -> bool:
	if _headless == -1:
		_headless = 1 if DisplayServer.get_name() == "headless" else 0
	return _headless == 0


static func emissive_material(color: Color, energy := 2.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func flat_material(color: Color, roughness := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


## Material for particles: colours come from the particle colour / ramp.
static func particle_material(unshaded := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func low_poly_sphere(radius: float, segments := 8, rings := 4) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segments
	s.rings = rings
	return s


static func fade_ramp(from: Color, to: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, Color(to.r, to.g, to.b, 0.0))
	return g


static func shrink_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0.1))
	return c


static func grow_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 1.0))
	return c


## One-shot burst of particles, auto-freed. Returns the emitter.
static func burst(parent: Node, at: Vector3, color: Color, amount := 16, speed := 6.0,
		size := 0.15, lifetime := 0.5, gravity := -12.0, box_mesh := true) -> CPUParticles3D:
	if parent == null or not particles_visible():
		return null
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.scale_amount_curve = shrink_curve()
	p.color_ramp = fade_ramp(color, color.darkened(0.6))
	p.mesh = shared_box(Vector3.ONE * size) if box_mesh else shared_sphere(size * 0.5, 6, 3)
	p.material_override = particle_material()
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	CombatUtil.free_after(p, lifetime + 0.3)
	return p


## Continuous world-space smoke trail; caller parents it and calls detach_trail later.
static func smoke_trail(color := Color(0.75, 0.75, 0.78, 0.7), amount := 40, lifetime := 0.7) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.local_coords = false
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector3(0, 1, 0)
	p.spread = 25.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.0
	p.gravity = Vector3(0, 0.8, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.3
	p.scale_amount_curve = grow_curve()
	p.color_ramp = fade_ramp(color, color)
	if particles_visible():
		p.mesh = shared_sphere(0.18, 6, 3)
	p.material_override = particle_material()
	p.emitting = particles_visible()
	return p


## Moves a trail to `new_parent` keeping its world transform, stops it and frees it later.
static func detach_trail(trail: CPUParticles3D, new_parent: Node) -> void:
	if trail == null or not is_instance_valid(trail) or new_parent == null:
		return
	var gt := trail.global_transform
	trail.get_parent().remove_child(trail)
	new_parent.add_child(trail)
	trail.global_transform = gt
	trail.emitting = false
	CombatUtil.free_after(trail, trail.lifetime + 0.2)


## Short-lived flash light.
static func flash_light(parent: Node, at: Vector3, color: Color, energy := 4.0, light_range := 8.0, duration := 0.25) -> void:
	if parent == null:
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	parent.add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, duration)
	tw.tween_callback(l.queue_free)
