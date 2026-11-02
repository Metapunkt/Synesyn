@tool
extends RefCounted

class_name DimReduction

enum Method {
	PCA,  # Principal Component Analysis
	TSNE, # t-Distributed Stochastic Neighbor Embedding
	UMAP  # Uniform Manifold Approximation and Projection
}

# Principal Component Analysis for dimensionality reduction
static func pca(data: Array, target_dimensions: int = 3) -> Array:
	# Expects array of arrays, where each inner array is a feature vector
	# Returns array of reduced vectors
	
	if data.size() == 0:
		return []
	
	# 1. Calculate mean vector
	var n_features = data[0].size()
	var mean_vector = []
	for i in range(n_features):
		mean_vector.append(0.0)
	
	for sample in data:
		for i in range(n_features):
			mean_vector[i] += sample[i]
	
	for i in range(n_features):
		mean_vector[i] /= data.size()
	
	# 2. Center the data
	var centered_data = []
	for sample in data:
		var centered_sample = []
		for i in range(n_features):
			centered_sample.append(sample[i] - mean_vector[i])
		centered_data.append(centered_sample)
	
	# 3. Compute covariance matrix
	var covariance_matrix = []
	for i in range(n_features):
		var row = []
		for j in range(n_features):
			row.append(0.0)
		covariance_matrix.append(row)
	
	for sample in centered_data:
		for i in range(n_features):
			for j in range(n_features):
				covariance_matrix[i][j] += sample[i] * sample[j]
	
	for i in range(n_features):
		for j in range(n_features):
			covariance_matrix[i][j] /= data.size() - 1
	
	# 4. Compute eigenvectors and eigenvalues
	# Note: For a full implementation, we'd use a library for eigendecomposition
	# This is a simplified version that approximates the first 3 principal components
	var principal_components = _approximate_principal_components(covariance_matrix, target_dimensions)
	
	# 5. Project data onto principal components
	var reduced_data = []
	for sample in centered_data:
		var reduced_sample = []
		for pc in principal_components:
			var projection = 0.0
			for i in range(n_features):
				projection += sample[i] * pc[i]
			reduced_sample.append(projection)
		reduced_data.append(reduced_sample)
	
	return reduced_data

# t-SNE with pairwise affinity computation and Student-t kernel.
# Not a textbook implementation but substantially better than PCA + naive forces.
static func tsne(data: Array, target_dimensions: int = 3, perplexity: float = 30.0, iterations: int = 300) -> Array:
	var n := data.size()
	if n == 0:
		return []

	# Clamp perplexity to dataset size
	perplexity = minf(perplexity, float(n - 1))

	# 1) Compute pairwise squared distances in high-D
	var hd_dist2: Array = []  # n x n
	for i in range(n):
		var row: Array = []
		for j in range(n):
			if i == j:
				row.append(0.0)
			else:
				var d2 := 0.0
				for f in range(data[i].size()):
					var diff: float = data[i][f] - data[j][f]
					d2 += diff * diff
				row.append(d2)
		hd_dist2.append(row)

	# 2) Compute symmetric affinities P via binary search for sigma per point
	var p_matrix: Array = []  # n x n
	for i in range(n):
		p_matrix.append(_compute_affinities_row(hd_dist2[i], i, perplexity))
	# Symmetrise: P_ij = (p_i|j + p_j|i) / (2n)
	for i in range(n):
		for j in range(i + 1, n):
			var sym: float = (p_matrix[i][j] + p_matrix[j][i]) / (2.0 * n)
			p_matrix[i][j] = sym
			p_matrix[j][i] = sym

	# 3) Initialise Y from PCA
	var y: Array = pca(data, target_dimensions)
	var y_prev: Array = []
	for i in range(n):
		y_prev.append(y[i].duplicate())

	# 4) Gradient descent with momentum
	var lr := 200.0
	var momentum := 0.5
	for t in range(iterations):
		if t == 100:
			momentum = 0.8  # Increase momentum after early phase

		# Compute Q (Student-t kernel in low-D)
		var q_num: Array = []  # n x n
		var q_sum := 0.0
		for i in range(n):
			var row: Array = []
			for j in range(n):
				if i == j:
					row.append(0.0)
				else:
					var d2 := 0.0
					for d in range(target_dimensions):
						var diff: float = y[i][d] - y[j][d]
						d2 += diff * diff
					var val := 1.0 / (1.0 + d2)
					row.append(val)
					q_sum += val
			q_num.append(row)
		if q_sum < 1e-12:
			q_sum = 1e-12

		# Compute gradient
		var grad: Array = []
		for i in range(n):
			var g: Array = []
			for d in range(target_dimensions):
				g.append(0.0)
			for j in range(n):
				if i == j:
					continue
				var q_ij: float = q_num[i][j] / q_sum
				var mult: float = 4.0 * (p_matrix[i][j] - q_ij) * q_num[i][j]
				for d in range(target_dimensions):
					g[d] += mult * (y[i][d] - y[j][d])
			grad.append(g)

		# Update with momentum
		for i in range(n):
			for d in range(target_dimensions):
				var new_val: float = y[i][d] - lr * grad[i][d] + momentum * (y[i][d] - y_prev[i][d])
				y_prev[i][d] = y[i][d]
				y[i][d] = new_val

	return y

# Binary search for sigma to match target perplexity for one row.
static func _compute_affinities_row(dist2_row: Array, idx: int, target_perplexity: float) -> Array:
	var n := dist2_row.size()
	var target_entropy := log(target_perplexity)
	var sigma := 1.0
	var lo := 1e-10
	var hi := 1e4
	var p_row: Array = []
	p_row.resize(n)

	for _bs in range(50):  # Binary search iterations
		var sum_exp := 0.0
		for j in range(n):
			if j == idx:
				p_row[j] = 0.0
			else:
				p_row[j] = exp(-dist2_row[j] / (2.0 * sigma * sigma))
				sum_exp += p_row[j]
		if sum_exp < 1e-12:
			sum_exp = 1e-12
		# Normalise and compute entropy
		var entropy := 0.0
		for j in range(n):
			p_row[j] /= sum_exp
			if p_row[j] > 1e-12:
				entropy -= p_row[j] * log(p_row[j])
		if absf(entropy - target_entropy) < 1e-5:
			break
		if entropy > target_entropy:
			hi = sigma
			sigma = (lo + hi) / 2.0
		else:
			lo = sigma
			sigma = (lo + hi) / 2.0
	return p_row

# UMAP with fuzzy simplicial-set membership weights and SGD optimisation.
static func umap(data: Array, target_dimensions: int = 3, n_neighbors: int = 15, iterations: int = 200) -> Array:
	var n := data.size()
	if n == 0:
		return []
	n_neighbors = mini(n_neighbors, n - 1)

	# 1) Compute pairwise distances
	var dists: Array = []  # n x n
	for i in range(n):
		var row: Array = []
		for j in range(n):
			if i == j:
				row.append(0.0)
			else:
				var d2 := 0.0
				for f in range(data[i].size()):
					var diff: float = data[i][f] - data[j][f]
					d2 += diff * diff
				row.append(sqrt(d2))
		dists.append(row)

	# 2) For each point, find k nearest neighbors and compute fuzzy membership weights.
	#    w(i,j) = exp(-(d(i,j) - rho_i) / sigma_i)   where rho_i = dist to 1st neighbor
	#    sigma_i is found via binary search to match log2(k) target.
	var weights: Dictionary = {}  # {i*n + j: weight}  sparse
	for i in range(n):
		# Sort neighbors by distance
		var nbr_dists: Array = []
		for j in range(n):
			if i != j:
				nbr_dists.append([j, dists[i][j]])
		nbr_dists.sort_custom(func(a, b): return a[1] < b[1])
		var knn: Array = nbr_dists.slice(0, n_neighbors)
		var rho_i: float = knn[0][1] if not knn.is_empty() else 0.0

		# Binary search for sigma_i
		var target_sum := log(float(n_neighbors)) / log(2.0)
		var sigma_i := 1.0
		var lo_s := 1e-10
		var hi_s := 1e4
		for _bs in range(50):
			var current_sum := 0.0
			for entry in knn:
				var d_ij: float = entry[1]
				var gap := maxf(d_ij - rho_i, 0.0)
				current_sum += exp(-gap / sigma_i)
			if absf(current_sum - target_sum) < 1e-5:
				break
			if current_sum > target_sum:
				hi_s = sigma_i
			else:
				lo_s = sigma_i
			sigma_i = (lo_s + hi_s) / 2.0

		for entry in knn:
			var j_idx: int = entry[0]
			var d_ij: float = entry[1]
			var gap := maxf(d_ij - rho_i, 0.0)
			var w := exp(-gap / sigma_i)
			weights[i * n + j_idx] = w

	# 3) Symmetrise weights:  W_sym(i,j) = w(i,j) + w(j,i) - w(i,j)*w(j,i)
	var sym_edges: Array = []  # [{i, j, w}]
	var seen_pairs: Dictionary = {}
	for key in weights:
		var i: int = int(key) / n
		var j: int = int(key) % n
		var pair_key := mini(i, j) * n + maxi(i, j)
		if seen_pairs.has(pair_key):
			continue
		seen_pairs[pair_key] = true
		var w_ij: float = weights.get(i * n + j, 0.0)
		var w_ji: float = weights.get(j * n + i, 0.0)
		var w_sym := w_ij + w_ji - w_ij * w_ji
		if w_sym > 1e-8:
			sym_edges.append({"i": i, "j": j, "w": w_sym})

	# 4) Initialise from PCA
	var y: Array = pca(data, target_dimensions)

	# 5) SGD optimisation: attractive + repulsive (negative sampling)
	var a_param := 1.0
	var b_param := 1.0
	for t in range(iterations):
		var alpha := 1.0 - float(t) / float(iterations)
		alpha = maxf(alpha, 0.01)
		# Attractive: for each edge, pull together
		for edge in sym_edges:
			var ei: int = edge["i"]
			var ej: int = edge["j"]
			var ew: float = edge["w"]
			var d2 := 0.0
			for d in range(target_dimensions):
				var diff: float = y[ei][d] - y[ej][d]
				d2 += diff * diff
			var grad_coeff := -2.0 * a_param * b_param * pow(d2, b_param - 1.0) / (a_param * pow(d2, b_param) + 1.0 + 1e-12)
			grad_coeff *= ew
			for d in range(target_dimensions):
				var diff: float = y[ei][d] - y[ej][d]
				var g: float = clampf(grad_coeff * diff * alpha, -4.0, 4.0)
				y[ei][d] -= g
				y[ej][d] += g

		# Repulsive: sample a few negative pairs per point
		var neg_samples := 5
		for i in range(n):
			for _ns in range(neg_samples):
				var j: int = randi() % n
				if j == i:
					continue
				var d2 := 0.0
				for d in range(target_dimensions):
					var diff: float = y[i][d] - y[j][d]
					d2 += diff * diff
				var rep_coeff := 2.0 * b_param / ((0.001 + d2) * (a_param * pow(d2, b_param) + 1.0 + 1e-12))
				for d in range(target_dimensions):
					var diff: float = y[i][d] - y[j][d]
					var g: float = clampf(rep_coeff * diff * alpha, -4.0, 4.0)
					y[i][d] += g

	return y

# Helper function to approximate principal components
static func _approximate_principal_components(covariance_matrix: Array, n_components: int) -> Array:
	var n_features = covariance_matrix.size()
	var components = []
	
	# Power iteration method to find dominant eigenvectors
	for comp_idx in range(n_components):
		# Initialize random vector
		var vector = []
		for i in range(n_features):
			vector.append(randf() * 2.0 - 1.0)
		
		# Normalize
		var norm = 0.0
		for i in range(n_features):
			norm += vector[i] * vector[i]
		norm = sqrt(norm)
		for i in range(n_features):
			vector[i] /= norm
		
		# Power iteration
		for iter_idx in range(10):  # Number of iterations for convergence
			var new_vector = []
			for i in range(n_features):
				new_vector.append(0.0)
			
			# Matrix-vector multiplication
			for i in range(n_features):
				for j in range(n_features):
					new_vector[i] += covariance_matrix[i][j] * vector[j]
			
			# Normalize
			norm = 0.0
			for i in range(n_features):
				norm += new_vector[i] * new_vector[i]
			norm = sqrt(norm)
			for i in range(n_features):
				new_vector[i] /= norm
			
			vector = new_vector
		
		# Deflate covariance matrix
		var deflated_matrix = []
		for i in range(n_features):
			var row = []
			for j in range(n_features):
				row.append(covariance_matrix[i][j] - vector[i] * vector[j])
			deflated_matrix.append(row)
		
		covariance_matrix = deflated_matrix
		components.append(vector)
	
	return components

# Convert array of arrays to array of Vector3 objects
static func _convert_to_vector3_array(data: Array) -> Array:
	var result = []
	
	for vec in data:
		var v3 = Vector3.ZERO
		for i in range(min(vec.size(), 3)):
			match i:
				0: v3.x = vec[i]
				1: v3.y = vec[i]
				2: v3.z = vec[i]
		result.append(v3)
	
	# Scale to a reasonable range
	return _scale_vectors(result, 5.0)

# Scale vectors to a reasonable range
static func _scale_vectors(vectors: Array, scale: float) -> Array:
	var result = []
	
	# Find min and max
	var min_vals = Vector3(INF, INF, INF)
	var max_vals = Vector3(-INF, -INF, -INF)
	
	for v in vectors:
		min_vals.x = min(min_vals.x, v.x)
		min_vals.y = min(min_vals.y, v.y)
		min_vals.z = min(min_vals.z, v.z)
		
		max_vals.x = max(max_vals.x, v.x)
		max_vals.y = max(max_vals.y, v.y)
		max_vals.z = max(max_vals.z, v.z)
	
	# Calculate ranges
	var ranges = max_vals - min_vals
	
	# Scale and center
	for v in vectors:
		var scaled = Vector3.ZERO
		
		if ranges.x > 0:
			scaled.x = ((v.x - min_vals.x) / ranges.x - 0.5) * scale
		if ranges.y > 0:
			scaled.y = ((v.y - min_vals.y) / ranges.y - 0.5) * scale
		if ranges.z > 0:
			scaled.z = ((v.z - min_vals.z) / ranges.z - 0.5) * scale
		
		result.append(scaled)
	
	return result

# Main function to reduce dimensionality of input vectors
static func reduce_dimensionality(input_vectors: Array, method: int = Method.PCA) -> Array:
	if input_vectors.size() == 0:
		return []
	
	var result = []
	
	match method:
		Method.PCA:
			var reduced_data = pca(input_vectors, 3)
			result = _convert_to_vector3_array(reduced_data)
		Method.TSNE:
			var reduced_data = tsne(input_vectors, 3)
			result = _convert_to_vector3_array(reduced_data)
		Method.UMAP:
			var reduced_data = umap(input_vectors, 3)
			result = _convert_to_vector3_array(reduced_data)
		_:
			var reduced_data = pca(input_vectors, 3)  # Default to PCA
			result = _convert_to_vector3_array(reduced_data)
	
	return result 