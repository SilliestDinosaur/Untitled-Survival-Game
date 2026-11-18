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
	# The channel's cut: the raw river depth, spread to the 3x3 cells around each cell.
	var channel := PackedFloat32Array()
	channel.resize(total)
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
			channel[j * n + i] = best
	# River cells: where the water runs (a river, not a lake). Each bed starts at its channel's cut.
	var river := PackedByteArray()
	river.resize(total)
	var bed := PackedFloat32Array()
	bed.resize(total)
	for k in total:
		# (A cell right at sea level has no room to cut a channel, so it's ground, not river.)
		if channel[k] > 0.0 and lake[k] == 0.0 and h[k] > Game.SEA_LEVEL + BED_FLOOR + 0.1:
			river[k] = 1
			bed[k] = h[k] - channel[k]
	# Gullies: a river holds its water at its bed plus the water's depth, and that must stay under the dry ground
	# beside it, or the water stands over that ground. Where the ground beside a river is lower, its bed drops.
	for k in total:
		if river[k] == 0:
			continue
		var gi: int = k % n
		var gj: int = k / n
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				var ni: int = gi + di
				var nj: int = gj + dj
				if ni < 0 or nj < 0 or ni >= n or nj >= n:
					continue
				var m: int = nj * n + ni
				if river[m] == 0 and h[m] > 0.0:
					bed[k] = minf(bed[k], h[m] - MAX_WATER_DEPTH + CLEARANCE)
	for k in total:
		if river[k] == 1:
			bed[k] = maxf(bed[k], Game.SEA_LEVEL + BED_FLOOR)
	# The cut each river makes: its ground down to its bed.
	var cut := PackedFloat32Array()
	cut.resize(total)
	for k in total:
		if river[k] == 1:
			cut[k] = h[k] - bed[k]
	# Banks: the ground beside a river is cut down with it, BANK_SLOPE per step away, but never below the water's
	# level there. Ground already under that level is left alone (the gully above has made the river drop to it).
	var beside := PackedByteArray()
	beside.resize(total)
	var lower := PackedFloat32Array()
	lower.resize(total)
	var room := PackedFloat32Array()
	room.resize(total)
	room.fill(1000.0)
	for k in total:
		if river[k] == 0:
			continue
		var bi: int = k % n
		var bj: int = k / n
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				if di == 0 and dj == 0:
					continue
				var ni: int = bi + di
				var nj: int = bj + dj
				if ni < 0 or nj < 0 or ni >= n or nj >= n:
					continue
				var m: int = nj * n + ni
				if river[m] == 1 or h[m] <= 0.0:
					continue
				var step := 1.0 if (di == 0 or dj == 0) else 1.414
				beside[m] = 1
				lower[m] = maxf(lower[m], cut[k] - BANK_SLOPE * step)
				room[m] = minf(room[m], h[m] - (bed[k] + MAX_WATER_DEPTH - CLEARANCE))
	var lake_cap := PackedFloat32Array()
	lake_cap.resize(total)
	lake_cap.fill(1000.0)
	for k in total:
		if lake[k] <= 0.0:
			continue
		var li: int = k % n
		var lj: int = k / n
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				if di == 0 and dj == 0:
					continue
				var ni: int = li + di
				var nj: int = lj + dj
				if ni < 0 or nj < 0 or ni >= n or nj >= n:
					continue
				var m: int = nj * n + ni
				if lake[m] == 0.0 and river[m] == 0 and h[m] > 0.0:
					lake_cap[m] = minf(lake_cap[m], h[m] - (lake[k] - CLEARANCE))
	var queue := PackedInt32Array()
	for k in total:
		if beside[k] == 1:
			cut[k] = clampf(lower[k], 0.0, maxf(minf(room[k], lake_cap[k]), 0.0))
			queue.append(k)
	# Ground further out: the bank slope carries on from the cut beside it.
	var head := 0
	while head < queue.size():
		var k: int = queue[head]
		head += 1
		var ci: int = k % n
		var cj: int = k / n
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				if di == 0 and dj == 0:
					continue
				var ni: int = ci + di
				var nj: int = cj + dj
				if ni < 0 or nj < 0 or ni >= n or nj >= n:
					continue
				var m: int = nj * n + ni
				if river[m] == 1 or beside[m] == 1 or h[m] <= 0.0:
					continue
				var step := 1.0 if (di == 0 or dj == 0) else 1.414
				var cand := minf(cut[k] - BANK_SLOPE * step, maxf(lake_cap[m], 0.0))
				if cand > cut[m] + 0.000001:
					cut[m] = cand
					queue.append(m)
	# The channel for the water: each river cell's cut (zero elsewhere).
	for k in total:
		channel[k] = cut[k] if river[k] == 1 else 0.0
	# River water: the depth of water in each river cell above its bed, at most MAX_WATER_DEPTH.
	var water := PackedFloat32Array()
	water.resize(total)
	for k in total:
		if river[k] == 1:
			var d := minf(channel[k] * WATER_FRACTION, MAX_WATER_DEPTH)
			water[k] = d if d >= MIN_WATER else 0.0
	# The water stays under the dry land beside it: a river cell's level can't stand above a neighbour's ground.
	# (River neighbours are left to the gullies above; a dry river cell passes no limit on, or the whole river would dry.)
	for k in total:
		if river[k] == 0 or water[k] <= 0.0:
			continue
		var wi: int = k % n
		var wj: int = k / n
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				if di == 0 and dj == 0:
					continue
				var ni: int = wi + di
				var nj: int = wj + dj
				if ni < 0 or nj < 0 or ni >= n or nj >= n:
					continue
				var m: int = nj * n + ni
				if lake[m] != 0.0 or river[m] == 1 or h[m] <= 0.0:
					continue
				var cap := h[m] + CLEARANCE - bed[k]
				if cap < water[k]:
					water[k] = cap if cap >= MIN_WATER else 0.0
	return {"n": n, "depth": cut, "water": water, "channel": channel, "lake": lake, "catchment": catch}


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
const MAX_WATER_DEPTH := 0.45  ## the deepest a river runs; the ground beside it is cut to hold that much
const BED_FLOOR := 0.02         ## river beds and the ground cut beside them stay this far above the sea (WorldGen uses it too)
const CLEARANCE := 0.05        ## how far under the dry ground beside a river its water must stay (the flood tolerance)
const MIN_WATER := 0.02        ## shallower than this, there's no water (the bank is dry)
const LAKE_MIN := 0.05         ## a pit that fills by more than this is a lake
const LAKE_MAX := 1.0          ## deeper basins are not lakes: the river breaches and runs through them instead


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
