class_name Hydrology
extends RefCounted
## Rivers from drainage. The island is sampled on a coarse grid; every cell sends its rain to its
## steepest downhill neighbour, and the water collected by each cell (its catchment) grows as it
## flows downhill. Where the catchment is big enough there is a river: the valley is cut deeper with
## the size of the river, and the river's surface is laid on top. Deterministic from the seed.

const CELL := 8.0          ## metres between samples
const RIVER_CATCHMENT := 160.0   ## cells of catchment before a stream counts as a river
const BIN := 0.25          ## height step used to sort cells from high to low


## Build the grid: returns {n, depth (metres to cut into the valley), channel (the cut of the river
## itself), water (metres of river water above the carved bed, 0 where there's none), lake (the surface
## height of a lake, 0 where there's none), catchment}. `gen` must have no rivers yet (see WorldGen).
static func compute(gen: WorldGen) -> Dictionary:
	var n := int(Game.WORLD_SIZE / CELL) + 1
	var total := n * n
	var h := PackedFloat32Array()
	h.resize(total)
	for j in n:
		for i in n:
			h[j * n + i] = gen.get_base_height(i * CELL, j * CELL)
	# Drainage: every cell passes its water to a neighbour that leads to the sea. Pits (basins with no way
	# out) fill up to the height where they spill over, so the water drains through the spill instead of
	# pooling; a filled pit is a lake at its spill height.
	var flood := _flood(h, n)
	var fill: PackedFloat32Array = flood.fill
	var parent: PackedInt32Array = flood.parent
	var order: PackedInt32Array = flood.order
	# Catchment: each land cell's rain, passed down to its parent. Children are settled after their parent,
	# so walking the settle order backwards counts every cell's upstream water before it moves on.
	var catch := PackedFloat32Array()
	catch.resize(total)
	for k in total:
		catch[k] = 1.0 if h[k] > 0.0 else 0.0
	for idx in range(total - 1, -1, -1):
		var k := order[idx]
		var p := parent[k]
		if p >= 0:
			catch[p] += catch[k]
	# Lakes: basins the flood had to fill, shallow enough to hold water (see _lakes).
	var lake := _lakes(h, fill, n)
	# Rivers: land with enough catchment, and not a lake. Depth grows with the river's size, and the
	# valley banks are widened a little so the river sits in a real valley, not a ditch.
	var raw := PackedFloat32Array()
	raw.resize(total)
	for k in total:
		if h[k] > 0.0 and catch[k] >= RIVER_CATCHMENT and lake[k] == 0.0:
			var size := log(catch[k] / RIVER_CATCHMENT + 1.0) / log(2.0)
			raw[k] = clampf(0.9 + size * 0.9, 0.9, 3.2)
	var depth := PackedFloat32Array()
	depth.resize(total)
	for j in n:
		for i in n:
			var best := 0.0
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					var ni: int = i + di
					var nj: int = j + dj
					if ni < 0 or nj < 0 or ni >= n or nj >= n:
						continue
					var w := 1.0 if (di == 0 and dj == 0) else 0.45
					best = maxf(best, raw[nj * n + ni] * w)
			depth[j * n + i] = best
	# The river itself: the cut channel before the banks spread out (this is where the water goes).
	var channel := PackedFloat32Array()
	channel.resize(total)
	for k in total:
		channel[k] = depth[k]
	# Banks: a cell can't be much shallower than its deepest neighbour, so the channel slopes out
	# into the land over tens of metres (like a real valley) instead of dropping in one step.
	depth = _relax_banks(depth, n)
	# River water: the depth of water in each river cell, above the carved bed. It's kept shallower than
	# the bank can hold (MAX_WATER_DEPTH): a deeper river would stand over the ground beside it.
	var water := PackedFloat32Array()
	water.resize(total)
	for k in total:
		if channel[k] > 0.0 and lake[k] == 0.0:
			var d := minf(channel[k] * WATER_FRACTION, MAX_WATER_DEPTH)
			water[k] = d if d >= MIN_WATER else 0.0
	return {"n": n, "depth": depth, "water": water, "channel": channel, "lake": lake, "catchment": catch}


## Priority-flood: settles every cell in order of the lowest height it can drain to. Outlets are the sea
## and the island's edge. A cell's fill is the height its water stands at (its own height unless it sits in
## a pit); parent is the neighbour the water leaves through, and order lists the cells in settle order.
static func _flood(h: PackedFloat32Array, n: int) -> Dictionary:
	var total := n * n
	var fill := PackedFloat32Array()
	fill.resize(total)
	var parent := PackedInt32Array()
	parent.resize(total)
	parent.fill(-1)
	var seen := PackedByteArray()
	seen.resize(total)
	var order := PackedInt32Array()
	order.resize(total)
	var heap := _Heap.new()
	for k in total:
		var i := k % n
		var j := k / n
		if h[k] <= Game.SEA_LEVEL or i == 0 or j == 0 or i == n - 1 or j == n - 1:
			seen[k] = 1
			fill[k] = h[k]
			heap.push(h[k], k)
	var settled := 0
	while not heap.is_empty():
		var c := heap.pop()
		var level := heap.last_key
		order[settled] = c
		settled += 1
		var ci := c % n
		var cj := c / n
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				if di == 0 and dj == 0:
					continue
				var ni: int = ci + di
				var nj: int = cj + dj
				if ni < 0 or nj < 0 or ni >= n or nj >= n:
					continue
				var nb := nj * n + ni
				if seen[nb] == 1:
					continue
				seen[nb] = 1
				parent[nb] = c
				fill[nb] = maxf(h[nb], level)
				heap.push(fill[nb], nb)
	return {"fill": fill, "parent": parent, "order": order}


## Lakes: a basin is the land cells the flood raised to one spill height, joined to each other. It holds a lake
## only when none of it lies deeper than LAKE_MAX; then the water stands at the spill height over every cell of
## the basin that lies under it. A basin with a deeper part is not a lake: the river breaches it instead. Judging
## the whole basin at once means a lake's water never stands over dry ground beside it.
static func _lakes(h: PackedFloat32Array, fill: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var total := n * n
	var lake := PackedFloat32Array()
	lake.resize(total)
	var seen := PackedByteArray()
	seen.resize(total)
	for start in total:
		if seen[start] == 1 or h[start] <= 0.0:
			continue
		var level: float = fill[start]
		var basin := PackedInt32Array()
		var stack := PackedInt32Array([start])
		seen[start] = 1
		var deepest := 0.0
		while not stack.is_empty():
			var c: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			basin.append(c)
			deepest = maxf(deepest, level - h[c])
			var ci: int = c % n
			var cj: int = c / n
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					var ni: int = ci + di
					var nj: int = cj + dj
					if ni < 0 or nj < 0 or ni >= n or nj >= n:
						continue
					var m: int = nj * n + ni
					if seen[m] == 0 and h[m] > 0.0 and fill[m] == level:
						seen[m] = 1
						stack.append(m)
		if deepest > LAKE_MIN and deepest <= LAKE_MAX:
			for c: int in basin:
				if level - h[c] > LAKE_MIN:
					lake[c] = level
	return lake


## A binary min-heap of (key, value) pairs, for the flood.
class _Heap extends RefCounted:
	var keys := PackedFloat32Array()
	var vals := PackedInt32Array()
	var last_key := 0.0

	func is_empty() -> bool:
		return keys.is_empty()

	func push(key: float, val: int) -> void:
		keys.append(key)
		vals.append(val)
		var i := keys.size() - 1
		while i > 0:
			var parent := (i - 1) / 2
			if keys[parent] <= keys[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> int:
		var top := vals[0]
		last_key = keys[0]
		var last := keys.size() - 1
		keys[0] = keys[last]
		vals[0] = vals[last]
		keys.resize(last)
		vals.resize(last)
		var i := 0
		var size := keys.size()
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < size and keys[l] < keys[m]:
				m = l
			if r < size and keys[r] < keys[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var tk := keys[a]
		keys[a] = keys[b]
		keys[b] = tk
		var tv := vals[a]
		vals[a] = vals[b]
		vals[b] = tv


## Bank slope: metres of depth lost per grid step away from the channel (a 4 m river has banks ~40 m wide).
const BANK_SLOPE := 0.6
const WATER_FRACTION := 0.35   ## the water surface sits this fraction of the channel depth above the bed
const MAX_WATER_DEPTH := 0.45  ## the deepest a river runs: banks rise about this much per cell, so deeper water would spill onto them
const MIN_WATER := 0.02        ## shallower than this, there's no water (the bank is dry)
const LAKE_MIN := 0.05         ## a pit that fills by more than this is a lake
const LAKE_MAX := 1.0          ## deeper basins are not lakes: the river breaches and runs through them instead


## Let the depth spread out from the channel, losing BANK_SLOPE per step. A breadth-first spread from
## the river cells: each cell hands its depth to its neighbours minus the slope, and only cells that
## actually improve are visited again. (Same result as repeated full sweeps, far less work.)
static func _relax_banks(depth: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var steps := [[-1, -1, 1.414], [0, -1, 1.0], [1, -1, 1.414], [-1, 0, 1.0], [1, 0, 1.0], [-1, 1, 1.414], [0, 1, 1.0], [1, 1, 1.414]]
	var queue := PackedInt32Array()
	for k in n * n:
		if depth[k] > 0.0:
			queue.append(k)
	var head := 0
	while head < queue.size():
		var k: int = queue[head]
		head += 1
		var i := k % n
		var j := k / n
		var dk: float = depth[k]
		for st: Array in steps:
			var ni: int = i + st[0]
			var nj: int = j + st[1]
			if ni < 0 or nj < 0 or ni >= n or nj >= n:
				continue
			var nk := nj * n + ni
			var cand: float = dk - BANK_SLOPE * float(st[2])
			if cand > depth[nk] + 0.000001:
				depth[nk] = cand
				queue.append(nk)
	return depth


## The water surface at each grid point, as the water mesh is built: `bed` is the carved ground there and
## `level` the surface height (0 where dry). A lake's level is its surface; a river's is its bed plus its depth.
static func surface(gen: WorldGen) -> Dictionary:
	var n: int = gen.hydro.n
	var lake: PackedFloat32Array = gen.hydro.lake
	var water: PackedFloat32Array = gen.hydro.water
	var bed := PackedFloat32Array()
	bed.resize(n * n)
	var level := PackedFloat32Array()
	level.resize(n * n)
	for j in n:
		for i in n:
			var k := j * n + i
			bed[k] = gen.get_base_height(i * CELL, j * CELL)
			if lake[k] > bed[k] + 0.02:
				level[k] = lake[k]
			elif water[k] > 0.0:
				level[k] = bed[k] + water[k]
	return {"bed": bed, "level": level}


## Dry land the water stands over: land grid points lying more than `tol` metres under the surface of a wet
## neighbour (ocean is left out). Returns {"count", "worst" (metres under the water), "at" (index of the worst)}.
static func flooded(gen: WorldGen, tol: float) -> Dictionary:
	var n: int = gen.hydro.n
	var surf := surface(gen)
	var bed: PackedFloat32Array = surf.bed
	var level: PackedFloat32Array = surf.level
	var count := 0
	var worst := 0.0
	var at := -1
	for k in n * n:
		if level[k] > 0.0 or bed[k] <= Game.SEA_LEVEL:
			continue
		var i := k % n
		var j := k / n
		var over := 0.0
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				var ni: int = i + di
				var nj: int = j + dj
				if ni < 0 or nj < 0 or ni >= n or nj >= n:
					continue
				var m := nj * n + ni
				if level[m] > 0.0:
					over = maxf(over, level[m] - bed[k])
		if over > tol:
			count += 1
			if over > worst:
				worst = over
				at = k
	return {"count": count, "worst": worst, "at": at}


## Sample a per-cell field at a world position (bilinear).
static func sample(field: PackedFloat32Array, n: int, x: float, z: float) -> float:
	var fx := clampf(x / CELL, 0.0, float(n - 1) - 0.001)
	var fz := clampf(z / CELL, 0.0, float(n - 1) - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := field[j * n + i]
	var b := field[j * n + i + 1]
	var c := field[(j + 1) * n + i]
	var d := field[(j + 1) * n + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)
