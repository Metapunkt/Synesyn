@tool
extends RefCounted
class_name TestDataGenerator

signal data_generated(data)

# Configuration
var _data_type: String = "text"  # Can be "text", "semantic", or "image"
var _item_count: int = 20
var _dimensions: int = 10  # For semantic vectors
var _include_metadata: bool = true

# Set the type of test data to generate
func set_data_type(type: String) -> void:
	_data_type = type

# Set the number of items to generate
func set_item_count(count: int) -> void:
	_item_count = count

# Set the dimensionality of vector data
func set_dimensions(dimensions: int) -> void:
	_dimensions = dimensions

# Generate test data based on the selected type
func generate_test_data() -> Array:
	var data = []
	
	match _data_type.to_lower():
		"text":
			data = _generate_text_data()
		"semantic":
			data = _generate_semantic_data()
		"image":
			data = _generate_image_data()
		_:
			data = _generate_text_data()
	
	emit_signal("data_generated", data)
	return data

# Generate sample text data
func _generate_text_data() -> Array:
	var text_samples = [
		"The quick brown fox jumps over the lazy dog.",
		"Machine learning is a fascinating field of study.",
		"Pattern recognition enables computers to identify structures in data.",
		"Natural language processing helps computers understand human language.",
		"Data visualization makes complex information easier to understand.",
		"Artificial intelligence aims to mimic human cognitive functions.",
		"Neural networks are inspired by the human brain's structure.",
		"Deep learning uses multiple layers to progressively extract features.",
		"Clustering algorithms group similar items together.",
		"Feature extraction identifies important aspects of the data.",
		"Dimensionality reduction simplifies complex data structures.",
		"Supervised learning uses labeled training data.",
		"Unsupervised learning finds patterns without labeled data.",
		"Reinforcement learning learns through interaction with an environment.",
		"Anomaly detection identifies unusual patterns in data.",
		"Time series analysis examines data points collected over time.",
		"Semantic analysis extracts meaning from text documents.",
		"Computer vision enables machines to interpret visual information.",
		"Speech recognition converts spoken language into text.",
		"Recommender systems suggest items based on user preferences."
	]
	
	var data = []
	var max_samples = min(_item_count, text_samples.size())
	
	for i in range(max_samples):
		var item = {
			"id": "text_" + str(i),
			"content": text_samples[i],
			"type": "text",
			"timestamp": Time.get_unix_time_from_system() - (i * 3600),  # Spread timestamps out
			"vector": _generate_random_vector(5)  # Small vector for text
		}
		
		if _include_metadata:
			item["metadata"] = {
				"source": "test_generator",
				"word_count": text_samples[i].split(" ").size(),
				"char_count": text_samples[i].length(),
				"category": ["information", "sample", "test"][i % 3]
			}
		
		data.append(item)
	
	# If we need more items than our samples, duplicate with variations
	while data.size() < _item_count:
		var base_idx = data.size() % max_samples
		var base_item = data[base_idx].duplicate(true)
		base_item["id"] = "text_" + str(data.size())
		base_item["timestamp"] = Time.get_unix_time_from_system() - (data.size() * 3600)
		base_item["vector"] = _generate_random_vector(5)
		data.append(base_item)
	
	return data

# Generate sample semantic data with vectors
func _generate_semantic_data() -> Array:
	var concepts = [
		"Machine Learning",
		"Data Science", 
		"Artificial Intelligence",
		"Neural Networks",
		"Pattern Recognition",
		"Computer Vision",
		"Natural Language Processing",
		"Deep Learning",
		"Reinforcement Learning",
		"Data Mining",
		"Information Retrieval",
		"Knowledge Representation",
		"Logic Programming",
		"Automated Reasoning",
		"Expert Systems",
		"Human-Computer Interaction",
		"Robotics",
		"Computer Graphics",
		"Virtual Reality",
		"Augmented Reality"
	]
	
	var data = []
	var max_concepts = min(_item_count, concepts.size())
	
	for i in range(max_concepts):
		var item = {
			"id": "semantic_" + str(i),
			"content": concepts[i],
			"type": "semantic",
			"timestamp": Time.get_unix_time_from_system() - (i * 3600),
			"vector": _generate_random_vector(_dimensions)
		}
		
		if _include_metadata:
			item["metadata"] = {
				"source": "test_generator",
				"category": ["ai", "data", "computing"][i % 3],
				"relevance": randf_range(0.7, 1.0)
			}
		
		data.append(item)
	
	# If we need more items than our samples, duplicate with variations
	while data.size() < _item_count:
		var base_idx = data.size() % max_concepts
		var base_item = data[base_idx].duplicate(true)
		base_item["id"] = "semantic_" + str(data.size())
		base_item["timestamp"] = Time.get_unix_time_from_system() - (data.size() * 3600)
		base_item["vector"] = _generate_random_vector(_dimensions)
		data.append(base_item)
	
	return data

# Generate sample image data (references to images)
func _generate_image_data() -> Array:
	var image_descriptions = [
		"Red square on white background",
		"Blue circle with yellow border",
		"Green triangle pointing upward",
		"Abstract pattern with various shapes",
		"Landscape with mountains and sky",
		"Portrait of a person smiling",
		"Dog sitting on grass",
		"Cat sleeping on a chair",
		"Building with many windows",
		"Beach with palm trees",
		"Forest with tall trees",
		"City skyline at night",
		"Sunset over the ocean",
		"Bridge crossing a river",
		"Road through a desert",
		"Flowers in a garden",
		"Fruit arranged in a bowl",
		"Computer on a desk",
		"Car parked on the street",
		"Books stacked on a shelf"
	]
	
	var data = []
	var max_images = min(_item_count, image_descriptions.size())
	
	for i in range(max_images):
		var item = {
			"id": "image_" + str(i),
			"content": image_descriptions[i],
			"type": "image",
			"timestamp": Time.get_unix_time_from_system() - (i * 3600),
			"vector": _generate_random_vector(_dimensions)
		}
		
		if _include_metadata:
			item["metadata"] = {
				"source": "test_generator",
				"width": randi_range(800, 1200),
				"height": randi_range(600, 900),
				"category": ["abstract", "nature", "object"][i % 3]
			}
		
		data.append(item)
	
	# If we need more items than our samples, duplicate with variations
	while data.size() < _item_count:
		var base_idx = data.size() % max_images
		var base_item = data[base_idx].duplicate(true)
		base_item["id"] = "image_" + str(data.size())
		base_item["timestamp"] = Time.get_unix_time_from_system() - (data.size() * 3600)
		base_item["vector"] = _generate_random_vector(_dimensions)
		data.append(base_item)
	
	return data

# Convenience alias used by plugin.gd — delegates to generate_test_data().
func regenerate_test_data() -> Array:
	return generate_test_data()

# Generate a random vector of the specified dimension
func _generate_random_vector(dimensions: int) -> Array:
	var vector = []
	for i in range(dimensions):
		vector.append(randf_range(-1.0, 1.0))
	return vector 