extends RefCounted

## Square minimum filter of the immutable natural surface. Two monotonic-queue
## passes are O(world columns), independent of radius. Published arrays are
## read-only, safe for both generation workers and main-thread block queries.
static func minimum_heights(heights: PackedInt32Array, side: int, radius: int) -> PackedByteArray:
	var intermediate := PackedByteArray()
	intermediate.resize(side*side)
	var result := PackedByteArray()
	result.resize(side*side)
	var queue := PackedInt32Array()
	queue.resize(side)
	for pass_index in 2:
		for row in side:
			var head := 0
			var tail := 0
			var right := -1
			for column in side:
				var limit := mini(side-1,column+radius)
				while right<limit:
					right += 1
					var index := row*side+right if pass_index==0 else right*side+row
					var value := heights[index] if pass_index==0 else int(intermediate[index])
					while tail>head:
						var prior := row*side+queue[tail-1] if pass_index==0 else queue[tail-1]*side+row
						var prior_value := heights[prior] if pass_index==0 else int(intermediate[prior])
						if prior_value<value: break
						tail -= 1
					queue[tail] = right
					tail += 1
				while queue[head]<column-radius: head += 1
				if pass_index==0: intermediate[row*side+column] = heights[row*side+queue[head]]
				else: result[column*side+row] = intermediate[queue[head]*side+row]
	return result
