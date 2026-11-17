class_name Hydrology
extends RefCounted
## Rivers from drainage. The island is sampled on a coarse grid; every cell sends its rain to its
## steepest downhill neighbour, and the water collected by each cell (its catchment) grows as it
## flows downhill. Where the catchment is big enough there is a river: the valley is cut deeper with
## the size of the river, and the river's surface is laid on top. Deterministic from the seed.

const CELL := 8.0          ## metres between samples
const RIVER_CATCHMENT := 38.0   ## cells of catchment before a stream counts as a river
const BIN := 0.25          ## height step used to sort cells from high to low


## Build the grid: returns {n, depth (metres to cut), water (metres of surface above the bed,
## 0 where there's no river), catchment}. `gen` must have no rivers yet (see WorldGen).
static func compute(gen: WorldGen) -> Dictionary:
	var n := int(Game.WORLD_SIZE / CELL) + 1
	var total := n * n
	var h := PackedFloat32Array()
	h.resize(total)
	var hmin := 1e9
	var hmax := -1e9
	for j in n:
		for i in n:
			var v := gen.get_base_height(i * CELL, j * CELL)
			h[j * n + i] = v
			hmin = minf(hmin, v)
			hmax = maxf(hmax, v)
	# Each land cell passes its water to the lowest neighbour (steepest descent).
	var recv := PackedInt32Array()
	recv.resize(total)
	for j in n:
		for i in n:
			var k := j * n + i
			var best := -1
			var best_slope := 0.0
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					if di == 0 and dj == 0:
						continue
					var ni: int = i + di
					var nj: int = j + dj
					if ni < 0 or nj < 0 or ni >= n or nj >= n:
						continue
					var drop := h[k] - h[nj * n + ni]
					var slope := drop / (CELL * sqrt(float(di * di + dj * dj)))
					if slope > best_slope:
						best_slope = slope
						best = nj * n + ni
			recv[k] = best
	# Catchment: visit cells from the highest down, so upstream water is counted before downstream.
	var nbins := int((hmax - hmin) / BIN) + 2
	var counts := PackedInt32Array()
	counts.resize(nbins + 1)
	var bin_of := PackedInt32Array()
	bin_of.resize(total)
	for k in total:
		var b := int((hmax - h[k]) / BIN)   # 0 = highest
		bin_of[k] = b
		counts[b + 1] += 1
	for b in nbins:
		counts[b + 1] += counts[b]
	var order := PackedInt32Array()
	order.resize(total)
	for k in total:
		var b := bin_of[k]
		order[counts[b]] = k
		counts[b] += 1
	var catch := PackedFloat32Array()
	catch.resize(total)
	for k in total:
		catch[k] = 1.0 if h[k] > 0.0 else 0.0
	for idx in total:
		var k := order[idx]
		var r := recv[k]
		if r >= 0:
			catch[r] += catch[k]
	# Rivers: cells with enough catchment on land. Depth grows with the river's size, and the
	# valley banks are widened a little so the river sits in a real valley, not a ditch.
	var raw := PackedFloat32Array()
	raw.resize(total)
	for k in total:
		if h[k] > 0.0 and catch[k] >= RIVER_CATCHMENT:
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
	# Banks: a cell can't be much shallower than its deepest neighbour, so the channel slopes out
	# into the land over tens of metres (like a real valley) instead of dropping in one step.
	depth = _relax_banks(depth, n)
	# Water surface: a river is a little less deep than its channel, so the bed shows under it.
	var water := PackedFloat32Array()
	water.resize(total)
	for k in total:
		water[k] = depth[k] * 0.45 if depth[k] > 0.3 else 0.0
	return {"n": n, "depth": depth, "water": water, "catchment": catch}


## Bank slope: metres of depth lost per grid step away from the channel (a 4 m river has banks ~40 m wide).
const BANK_SLOPE := 0.6
const BANK_PASSES := 8


## Let the depth spread out from the channel, losing BANK_SLOPE per step (forward and backward sweeps).
static func _relax_banks(depth: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var steps := [[-1, -1, 1.414], [0, -1, 1.0], [1, -1, 1.414], [-1, 0, 1.0], [1, 0, 1.0], [-1, 1, 1.414], [0, 1, 1.0], [1, 1, 1.414]]
	for pass_i in BANK_PASSES:
		var forward := pass_i % 2 == 0
		for jj in n:
			var j: int = jj if forward else n - 1 - jj
			for ii in n:
				var i: int = ii if forward else n - 1 - ii
				var k := j * n + i
				for st: Array in steps:
					var ni: int = i + st[0]
					var nj: int = j + st[1]
					if ni < 0 or nj < 0 or ni >= n or nj >= n:
						continue
					var cand: float = depth[nj * n + ni] - BANK_SLOPE * float(st[2])
					if cand > depth[k]:
						depth[k] = cand
	return depth


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
