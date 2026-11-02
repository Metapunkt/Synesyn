@tool
extends RefCounted

# Simple pattern discovery engine for Synaxes
class_name DiscoveryEngine

enum DiscoveryMethod {
	CLUSTERING,
	BRIDGE_ANALYSIS,
	HUB_IDENTIFICATION,
	CUSTOM
}

# Internal data storage
var _data = []
var _patterns = {}

func set_data(data: Array) -> void:
	_data = data
	
func get_pattern(pattern_id: int) -> Dictionary:
	if _patterns.has(pattern_id):
		return _patterns[pattern_id]
	return {}

func discover_patterns(method: int, dim_method: int, num_clusters: int = 5) -> Array:
	if _data.is_empty() or _data.size() == 0:
		push_error("No data to discover patterns from")
		return []
	
	# Extract feature vectors from data
	var feature_vectors = _extract_feature_vectors(_data)
	
	if feature_vectors.is_empty() or feature_vectors.size() == 0:
		push_error("Failed to extract feature vectors from data")
		return []
	
	# Reduce dimensionality
	var positions = _reduce_dimensionality(feature_vectors, dim_method)
	
	# Apply discovery method
	var patterns = []
	match method:
		DiscoveryMethod.CLUSTERING:
			patterns = _discover_clusters(positions, feature_vectors, _data, num_clusters)
		DiscoveryMethod.BRIDGE_ANALYSIS:
			patterns = _discover_bridges(positions, feature_vectors, _data)
		DiscoveryMethod.HUB_IDENTIFICATION:
			patterns = _discover_hubs(positions, feature_vectors, _data)
		_:
			push_error("Unknown discovery method")
	
	# Store patterns
	for pattern in patterns:
		_patterns[pattern.id] = pattern
	
	return patterns

# Extract feature vectors from data
func _extract_feature_vectors(data: Array) -> Array:
	var vectors = []
	
	for item in data:
		if item is Dictionary and item.has("vector"):
			vectors.append(item.vector)
		elif item is Dictionary and item.has("embedding"):
			vectors.append(item.embedding)
		else:
			# Generate a random vector as fallback
			var random_vector = []
			for i in range(10):  # 10-dimensional vectors
				random_vector.append(randf() * 2.0 - 1.0)
			vectors.append(random_vector)
	
	return vectors

# Reduce dimensionality of vectors
func _reduce_dimensionality(vectors: Array, method: int) -> Array:
	# Use DimReduction class for dimensionality reduction
	return DimReduction.reduce_dimensionality(vectors, method)

# Discover clusters in the data
func _discover_clusters(positions: Array, vectors: Array, data: Array, num_clusters: int) -> Array:
	var patterns = []
	
	# Simple k-means clustering
	# Initialize cluster centers randomly
	var cluster_centers = []
	for i in range(num_clusters):
		var random_index = randi() % positions.size()
		cluster_centers.append(positions[random_index])
	
	# Assign points to clusters
	var clusters = []
	for i in range(num_clusters):
		clusters.append([])
	
	for i in range(positions.size()):
		var min_dist = INF
		var closest_cluster = 0
		
		for j in range(num_clusters):
			var dist = positions[i].distance_to(cluster_centers[j])
			if dist < min_dist:
				min_dist = dist
				closest_cluster = j
		
		clusters[closest_cluster].append(i)
	
	# Create patterns from clusters with meaningful confidence scores
	for i in range(num_clusters):
		if clusters[i].is_empty() or clusters[i].size() == 0:
			continue
		
		# Calculate cluster center
		var center = Vector3.ZERO
		for point_idx in clusters[i]:
			center += positions[point_idx]
		center /= clusters[i].size()
		
		# Compute cluster confidence: cohesion (low intra-cluster spread = high confidence)
		var avg_intra_dist := 0.0
		for point_idx in clusters[i]:
			avg_intra_dist += positions[point_idx].distance_to(center)
		avg_intra_dist /= clusters[i].size()

		# Compute separation: distance from this cluster center to the nearest other center
		var min_inter_dist := INF
		for j in range(num_clusters):
			if i == j or clusters[j].is_empty():
				continue
			var other_center := Vector3.ZERO
			for point_idx in clusters[j]:
				other_center += positions[point_idx]
			other_center /= clusters[j].size()
			var inter_d: float = center.distance_to(other_center)
			if inter_d < min_inter_dist:
				min_inter_dist = inter_d

		# Silhouette-like confidence: high when items are close together and far from neighbours.
		# Ranges 0–1. If cluster is alone (no neighbours), confidence is based on cohesion alone.
		var conf := 0.5
		if min_inter_dist < INF and min_inter_dist > 0.001:
			# ratio > 1 means items closer to own centre than to nearest neighbour → good
			var ratio := min_inter_dist / (avg_intra_dist + 0.001)
			conf = clampf(ratio / (ratio + 1.0), 0.1, 1.0)
		elif avg_intra_dist < 0.5:
			conf = 0.9  # Very tight cluster
		
		# Bonus for larger clusters (more items = more signal)
		if clusters[i].size() >= 5:
			conf = minf(conf + 0.05, 1.0)
		
		# Create pattern
		var pattern_id = patterns.size()
		var cluster_items = []
		
		for point_idx in clusters[i]:
			cluster_items.append(data[point_idx])
		
		var pattern = {
			"id": pattern_id,
			"position": center,
			"type": "cluster",
			"confidence": snappedf(conf, 0.01),
			"items": cluster_items,
			"relations": []
		}
		
		patterns.append(pattern)
	
	# Create relationships between nearby clusters
	for i in range(patterns.size()):
		for j in range(i + 1, patterns.size()):
			var dist = patterns[i].position.distance_to(patterns[j].position)
			
			if dist < 3.0:  # Arbitrary threshold
				patterns[i].relations.append({
					"id": patterns[j].id,
					"type": "proximity",
					"strength": 1.0 - (dist / 3.0)
				})
				
				patterns[j].relations.append({
					"id": patterns[i].id,
					"type": "proximity",
					"strength": 1.0 - (dist / 3.0)
				})
	
	return patterns

# Discover bridges between clusters
func _discover_bridges(positions: Array, vectors: Array, data: Array) -> Array:
	var patterns = []
	
	# Find points that are between clusters
	# For simplicity, we'll just pick points that are far from others
	var distances = []
	
	for i in range(positions.size()):
		var avg_dist = 0.0
		for j in range(positions.size()):
			if i != j:
				avg_dist += positions[i].distance_to(positions[j])
		avg_dist /= positions.size() - 1
		
		distances.append({"index": i, "avg_dist": avg_dist})
	
	# Sort by average distance (descending)
	distances.sort_custom(func(a, b): return a.avg_dist > b.avg_dist)
	
	# Take top points as bridges
	var num_bridges = min(5, positions.size() / 10)
	for i in range(num_bridges):
		var point_idx = distances[i].index
		
		# Bridge confidence: higher when the point's average distance is notably above the dataset mean.
		var global_avg := 0.0
		for d_entry in distances:
			global_avg += d_entry["avg_dist"]
		global_avg /= distances.size()
		var bridge_conf := clampf(distances[i]["avg_dist"] / (global_avg + 0.001) - 0.5, 0.1, 1.0)

		var pattern_id = patterns.size()
		var pattern = {
			"id": pattern_id,
			"position": positions[point_idx],
			"type": "bridge",
			"confidence": snappedf(bridge_conf, 0.01),
			"items": [data[point_idx]],
			"relations": []
		}
		
		patterns.append(pattern)
	
	return patterns

# Discover hubs (points with many connections)
func _discover_hubs(positions: Array, vectors: Array, data: Array) -> Array:
	var patterns = []
	
	# For each point, count how many other points are nearby
	var connection_counts = []
	
	for i in range(positions.size()):
		var count = 0
		for j in range(positions.size()):
			if i != j and positions[i].distance_to(positions[j]) < 2.0:  # Arbitrary threshold
				count += 1
		
		connection_counts.append({"index": i, "count": count})
	
	# Sort by connection count (descending)
	connection_counts.sort_custom(func(a, b): return a.count > b.count)
	
	# Take top points as hubs
	var num_hubs = min(3, positions.size() / 20)
	for i in range(num_hubs):
		var point_idx = connection_counts[i].index
		
		# Hub confidence: proportion of dataset this point connects to.
		var hub_conf := clampf(float(connection_counts[i]["count"]) / float(positions.size()), 0.1, 1.0)

		var pattern_id = patterns.size()
		var pattern = {
			"id": pattern_id,
			"position": positions[point_idx],
			"type": "hub",
			"confidence": snappedf(hub_conf, 0.01),
			"items": [data[point_idx]],
			"relations": []
		}
		
		# Add connections to nearby points
		for j in range(positions.size()):
			if point_idx != j and positions[point_idx].distance_to(positions[j]) < 2.0:
				pattern.relations.append({
					"id": j,
					"type": "hub_connection",
					"strength": 1.0 - (positions[point_idx].distance_to(positions[j]) / 2.0)
				})
		
		patterns.append(pattern)
	
	return patterns 