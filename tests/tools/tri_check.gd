extends SceneTree
## Triangle check for item models: godot --headless --path . -s tests/tools/tri_check.gd
## For every item (or the ones in ITEMS), builds the mesh the way the game does and checks:
##   inverted  - the triangle's front face (clockwise, as Godot draws it) points away from its vertex normals,
##               so it vanishes or lights wrong from the side you see it on
##   degenerate - zero-area triangles
##   nan        - non-finite positions or normals
##   open       - edges used by only one triangle (cracks), counted after welding vertices by position
##   nonmanifold - edges used by three or more triangles
## Environment:
##   ITEMS=hatchet_t1,pickaxe_t2   check only these (default: every item in ItemDB)
##   VERBOSE=1                     list each bad triangle's index and position

var _main: Node
var _f := 0
var _started := false
var _done := false
var ItemModels: GDScript
var ArtStyle: GDScript


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	ItemModels = load("res://scripts/items/item_models.gd")
	ArtStyle = load("res://scripts/world/art_style.gd")


func _process(_d: float) -> bool:
	_f += 1
	if _done:
		return true
	if not _started:
		if _f == 5:
			_main.create_world("Tri Check", 629946553)
		if _main.state == _main.State.PLAYING:
			_started = true
			_run()
			_done = true
			return true
		return false
	return false


func _run() -> void:
	var ids: Array = []
	var only := OS.get_environment("ITEMS")
	if only != "":
		ids = only.split(",")
	else:
		ids = _all_ids()
	var mat: Material = ArtStyle.painted({"brush_strength": 0.1, "rim_amount": 0.3})
	var verbose := OS.get_environment("VERBOSE") != ""
	var total_bad := 0
	for id: String in ids:
		var mesh: ArrayMesh = ItemModels.mesh_for(id, mat)
		var report := _check(mesh, verbose, id)
		var bad: int = report.inverted + report.degenerate + report.nan + report.open + report.nonmanifold
		total_bad += bad
		print("%-14s tris %5d  inverted %4d (slivers %4d)  degenerate %3d  nan %3d  open %4d  nonmanifold %3d  slivers %4d  %s" % [
			id, report.tris, report.inverted, report.inverted_sliver, report.degenerate, report.nan, report.open, report.nonmanifold,
			report.sliver, "ok" if bad == 0 else "BAD"])
	print("RESULT: ", "PASS" if total_bad == 0 else "FAIL", " (%d problems)" % total_bad)
	quit()


func _all_ids() -> Array:
	var db = load("res://scripts/items/item_db.gd")
	return db.all_ids()


func _check(mesh: ArrayMesh, verbose: bool, id: String) -> Dictionary:
	var out := {"tris": 0, "inverted": 0, "degenerate": 0, "nan": 0, "open": 0, "nonmanifold": 0, "sliver": 0, "inverted_sliver": 0}
	if mesh == null or mesh.get_surface_count() == 0:
		return out
	var arrays := mesh.surface_get_arrays(0)
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var welded := {}
	var edges := {}
	var t := 0
	while t + 2 < pos.size():
		var a := pos[t]
		var b := pos[t + 1]
		var c := pos[t + 2]
		var na := nrm[t]
		var nb := nrm[t + 1]
		var nc := nrm[t + 2]
		out.tris += 1
		if not (_finite(a) and _finite(b) and _finite(c) and _finite(na) and _finite(nb) and _finite(nc)):
			out.nan += 1
			if verbose:
				print("   nan tri ", t / 3)
			t += 3
			continue
		var g := (c - a).cross(b - a)   # Godot front face: clockwise seen from the front
		if g.length_squared() < 1e-16:   # twice the area is under 10 nm: no area at all
			out.degenerate += 1
			t += 3
			continue
		var fn := g.normalized()
		var avg := (na + nb + nc)
		var longest := maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a)))
		var sliver := longest > 0.0 and g.length() / (longest * longest) < 0.05   # very thin: height under 5% of its length
		if sliver:
			out.sliver += 1
		if avg.length_squared() > 1e-12 and fn.dot(avg.normalized()) < 0.0:
			out.inverted += 1
			if sliver:
				out.inverted_sliver += 1
			if verbose:
				print("   inverted tri ", t / 3, " at ", (a + b + c) / 3.0)
				print("       verts ", a, " ", b, " ", c)
				print("       norms ", na, " ", nb, " ", nc, "  winding ", fn)
		# Edges, by welded position, so cracks show up as one-sided edges.
		var keys := [_key(a), _key(b), _key(c)]
		for e in 3:
			var k1: String = keys[e]
			var k2: String = keys[(e + 1) % 3]
			var ek := k1 + "|" + k2 if k1 < k2 else k2 + "|" + k1
			edges[ek] = int(edges.get(ek, 0)) + 1
		t += 3
	for ek: String in edges:
		var n: int = edges[ek]
		if n == 1:
			out.open += 1
			if verbose and out.open <= 8:
				print("   open edge ", ek)
		elif n >= 3:
			out.nonmanifold += 1
			if verbose:
				print("   nonmanifold edge ", ek, " used ", n)
	return out


func _key(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x * 20000.0), roundi(p.y * 20000.0), roundi(p.z * 20000.0)]


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
