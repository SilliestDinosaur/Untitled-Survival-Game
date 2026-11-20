extends SceneTree
## Triangle check for item models: godot --headless --path . -s tests/tools/tri_check.gd
## For every item (or the ones in ITEMS), builds the mesh the way the game does and checks:
##   inverted  - the triangle's front face (clockwise, as Godot draws it) points away from its vertex normals,
##               so it vanishes or lights wrong from the side you see it on
##   degenerate - zero-area triangles
##   nan        - non-finite positions or normals
##   open       - edges used by only one triangle (cracks), counted after welding vertices by position
##   nonmanifold - edges used by three or more triangles
##   zfight     - (ZFIGHT=1) separate triangles lying in the same plane, facing the same way and overlapping: two
##                surfaces fighting over the same pixels, so they flicker as the view moves
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
	if OS.get_environment("FLORA") != "":
		_run_flora()
		return
	if OS.get_environment("EXTRA") != "":
		_run_extra()
		return
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
		# Building pieces are checked as built (their item's model is only a stand-in).
		var mesh: ArrayMesh = load("res://scripts/world/structure_models.gd").get_model(id, mat, mat).body \
			if load("res://scripts/items/item_db.gd").info(id).get("kind", "") == "piece" and load("res://scripts/core/game_actions.gd").PIECES.has(id) \
			else ItemModels.mesh_for(id, mat)
		var report := _check(mesh, verbose, id)
		if OS.get_environment("ZFIGHT") != "":
			var z := _zfight(mesh, verbose)
			if z > 0:
				print("%-14s zfight %d" % [id, z])
				total_bad += z
			continue
		var bad: int = report.inverted + report.degenerate + report.nan + report.open + report.nonmanifold
		total_bad += bad
		print("%-14s tris %5d  inverted %4d (slivers %4d)  degenerate %3d  nan %3d  open %4d  nonmanifold %3d  slivers %4d  %s" % [
			id, report.tris, report.inverted, report.inverted_sliver, report.degenerate, report.nan, report.open, report.nonmanifold,
			report.sliver, "ok" if bad == 0 else "BAD"])
	print("RESULT: ", "PASS" if total_bad == 0 else "FAIL", " (%d problems)" % total_bad)
	quit()


## FLORA=1: every plant, tree and rock mesh (full, far twin and harvested look). Plants are open shells and leaf
## cards on purpose, so only inverted, degenerate and non-finite triangles count against them. Bushes, willows and
## other puffed canopies point their normals away from the crown's middle for soft shading, so the lumps' inward
## faces show as "inverted" by design; trees with tiers or blobs should show none. Not part of the suite.
func _run_flora() -> void:
	var flora = root.get_node("Game").flora
	var verbose := OS.get_environment("VERBOSE") != ""
	var only := OS.get_environment("KEYS")
	var total_bad := 0
	for key: String in flora.mesh_keys():
		if only != "" and not key in only.split(","):
			continue
		var report := _check(flora.mesh(key), verbose, key)
		if OS.get_environment("ZFIGHT") != "":
			var z := _zfight(flora.mesh(key), verbose)
			if z > 0:
				print("%-22s zfight %d" % [key, z])
				total_bad += z
			continue
		var bad: int = report.inverted + report.degenerate + report.nan
		total_bad += bad
		if bad > 0 or verbose:
			print("%-22s tris %6d  inverted %4d (slivers %4d)  degenerate %3d  nan %3d  %s" % [
				key, report.tris, report.inverted, report.inverted_sliver, report.degenerate, report.nan, "ok" if bad == 0 else "BAD"])
	print("RESULT: ", "PASS" if total_bad == 0 else "FAIL", " (%d problems in plant meshes)" % total_bad)
	quit()


## EXTRA=1 (with ZFIGHT=1): what the item and plant checks don't cover: everything built in the caves (supply
## chests, camps, dripstone, moss) and every animal's body, head and legs.
func _run_extra() -> void:
	var meshes := {}
	var walk := func(n: Node, f: Callable) -> void:
		for c in n.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is ArrayMesh:
				meshes["%s/%s" % [n.name, c.name]] = (c as MeshInstance3D).mesh
			f.call(c, f)
	var cf := _main.get_node_or_null("CaveFeatures")
	if cf:
		walk.call(cf, walk)
	var game := root.get_node("Game")
	for sp in game.fauna.species:
		for m in [sp.body_mesh, sp.head_mesh, sp.leg_mesh, sp.hind_leg_mesh, sp.wing_mesh]:
			if m:
				meshes["%s %d" % [sp.name, meshes.size()]] = m
	var total := 0
	var verbose := OS.get_environment("VERBOSE") != ""
	for key: String in meshes:
		var z := _zfight(meshes[key], verbose)
		if z > 0:
			print("%-30s zfight %d" % [key, z])
			total += z
	print("checked %d meshes" % meshes.size())
	print("RESULT: ", "PASS" if total == 0 else "FAIL", " (%d problems)" % total)
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


## Pairs of triangles that z-fight: same plane (within 0.01 mm: closer than the depth buffer can tell apart at
## play distances), same facing, overlapping, and not neighbours on one
## surface (they share no corner).
func _zfight(mesh: ArrayMesh, verbose: bool) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var pos: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var buckets := {}
	var tris: Array = []
	var floor_y := INF   # faces down on the model's very bottom rest on the ground: never seen
	for p in pos:
		floor_y = minf(floor_y, p.y)
	var t := 0
	while t + 2 < pos.size():
		var a := pos[t]
		var b := pos[t + 1]
		var c := pos[t + 2]
		t += 3
		var g := (c - a).cross(b - a)
		if g.length_squared() < 1e-12:
			continue
		var n := g.normalized()
		var d := n.dot(a)
		if n.y < -0.95 and absf(a.y - floor_y) < 0.002 and absf(b.y - floor_y) < 0.002:
			continue
		var i := tris.size()
		tris.append([a, b, c, n, d])
		var key := [roundi(n.x * 30.0), roundi(n.y * 30.0), roundi(n.z * 30.0), roundi(d * 20000.0)]
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(i)
	var found := 0
	var seen := {}
	for key: Array in buckets:
		var mine: Array = buckets[key]
		# Neighbouring distance bins too (two planes 1 mm apart can fall either side of a bin's edge).
		var others: Array = mine.duplicate()
		for dd in [-1, 1]:
			var k2 := [key[0], key[1], key[2], key[3] + dd]
			if buckets.has(k2):
				others.append_array(buckets[k2])
		if mine.size() * others.size() > 400000:
			continue   # a huge flat plane (a floor's top): its tiles don't overlap; skip the cost
		for i: int in mine:
			for j: int in others:
				if j <= i or seen.has(Vector2i(i, j)):
					continue
				seen[Vector2i(i, j)] = true
				var A: Array = tris[i]
				var B: Array = tris[j]
				if (A[3] as Vector3).dot(B[3]) < 0.998 or absf(float(A[4]) - float(B[4])) > 0.00001:
					continue
				if _shares_corner(A, B):
					continue
				if _overlap(A, B):
					found += 1
					if verbose and found <= int(OS.get_environment("SHOW") if OS.get_environment("SHOW") != "" else "6"):
						print("   zfight near ", (A[0] + A[1] + A[2]) / 3.0)
	return found


func _shares_corner(A: Array, B: Array) -> bool:
	for p in 3:
		for q in 3:
			if (A[p] as Vector3).distance_squared_to(B[q]) < 1e-10:
				return true
	return false


## Two coplanar triangles overlap with some area: a point well inside one lies inside the other.
func _overlap(A: Array, B: Array) -> bool:
	var n: Vector3 = A[3]
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u)
	var pa: Array = []
	var pb: Array = []
	for k in 3:
		pa.append(Vector2((A[k] as Vector3).dot(u), (A[k] as Vector3).dot(v)))
		pb.append(Vector2((B[k] as Vector3).dot(u), (B[k] as Vector3).dot(v)))
	for pair: Array in [[pa, pb], [pb, pa]]:
		var src: Array = pair[0]
		var dst: Array = pair[1]
		var cen: Vector2 = (src[0] + src[1] + src[2]) / 3.0
		for k in 4:
			var probe: Vector2 = cen if k == 3 else (src[k] as Vector2).lerp(cen, 0.35)
			if Geometry2D.point_is_inside_triangle(probe, dst[0], dst[1], dst[2]):
				return true
	return false


func _key(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x * 20000.0), roundi(p.y * 20000.0), roundi(p.z * 20000.0)]


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
