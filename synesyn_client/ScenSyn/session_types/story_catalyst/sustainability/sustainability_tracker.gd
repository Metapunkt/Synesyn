# res://ScenSyn/session_types/story_catalyst/sustainability/sustainability_tracker.gd
extends Node

signal metrics_updated(metrics)

# Define sustainability domains
enum Domain {ENERGY, COMMUNITY, INNOVATION, ENVIRONMENT, EQUITY}

# Core tracking properties
var metrics = {
	Domain.ENERGY: 0.0,      # Tracks focus on energy transition topics
	Domain.COMMUNITY: 0.0,   # Tracks community impact considerations
	Domain.INNOVATION: 0.0,  # Tracks discussion of new solutions
	Domain.ENVIRONMENT: 0.0, # Tracks environmental protection focus
	Domain.EQUITY: 0.0       # Tracks social justice aspects
}

# Keyword dictionaries for each domain
var domain_keywords = {
	Domain.ENERGY: [
		# Renewable sources
		"renewable", "wind", "solar", "hydroelectric", "geothermal", "biomass", "tidal", "wave",
		"photovoltaic", "turbine", "windmill", "hydropower", "clean energy", "green energy",
		# Traditional/fossil
		"fossil fuel", "coal", "oil", "gas", "natural gas", "petroleum", "carbon", "emissions",
		"nuclear", "uranium", "reactor",
		# Infrastructure
		"grid", "power", "electricity", "energy storage", "battery", "transmission", "distribution",
		"smart grid", "microgrid", "power plant", "generator", "transformer", "substation",
		# Energy transition terms
		"energy transition", "decarbonization", "carbon neutral", "net zero", "electrification",
		"heat pump", "district heating", "energy efficiency", "insulation", "retrofit",
		# Trondheim specific
		"fjord", "hydroelectric dam", "Trondheim Energi", "power grid", "heating system",
		# Consumption & efficiency
		"consumption", "demand", "supply", "peak load", "baseload", "storage", "backup",
		"efficiency", "conservation", "waste", "optimization", "smart meter"
	],
	
	Domain.COMMUNITY: [
		# General community terms
		"local", "residents", "neighborhood", "public", "citizens", "participation", "voices", "stakeholders",
		"community", "people", "families", "households", "neighbors", "locals", "inhabitants",
		# Participation & engagement
		"engagement", "involvement", "consultation", "feedback", "input", "opinion", "vote",
		"meeting", "workshop", "forum", "dialogue", "discussion", "debate", "consensus",
		# Social structures
		"social", "cultural", "traditional", "heritage", "identity", "belonging", "cohesion",
		"cooperation", "collaboration", "solidarity", "mutual aid", "support network",
		# Norwegian/Trondheim context
		"kommune", "bydel", "district", "Trondheim", "Norwegian", "Trøndelag", "fjord community",
		"city center", "downtown", "suburbs", "rural", "urban", "municipal", "local government",
		# Demographics
		"elderly", "youth", "children", "students", "workers", "families", "immigrants",
		"indigenous", "Sami", "minorities", "vulnerable groups", "low income",
		# Community services
		"schools", "healthcare", "transport", "services", "infrastructure", "facilities",
		"library", "community center", "park", "recreation"
	],
	
	Domain.INNOVATION: [
		# Research & development
		"research", "development", "new solution", "technology", "breakthrough", "efficiency", "invention",
		"innovation", "R&D", "experiment", "prototype", "pilot project", "testing", "trial",
		"discovery", "advancement", "progress", "cutting-edge", "state-of-the-art", "novel",
		# Technology types
		"artificial intelligence", "AI", "machine learning", "automation", "robotics", "IoT",
		"sensors", "monitoring", "data", "analytics", "modeling", "simulation", "digital",
		"blockchain", "cryptocurrency", "fintech", "cleantech", "greentech",
		# Academic & institutional
		"NTNU", "university", "research institute", "laboratory", "academia", "scientists",
		"engineers", "researchers", "students", "thesis", "publication", "patent",
		"startup", "entrepreneur", "venture", "funding", "investment", "incubator",
		# Innovation processes
		"design thinking", "agile", "lean", "iterative", "collaborative", "open source",
		"crowdsourcing", "hackathon", "competition", "challenge", "prize",
		# Implementation
		"scaling", "deployment", "adoption", "implementation", "rollout", "commercialization",
		"market", "business model", "viable", "sustainable", "profitable"
	],
	
	Domain.ENVIRONMENT: [
		# Natural systems
		"ecosystem", "biodiversity", "pollution", "emissions", "habitat", "conservation", "climate",
		"nature", "wildlife", "flora", "fauna", "species", "endangered", "extinction",
		"forest", "trees", "plants", "animals", "birds", "fish", "marine life",
		# Environmental issues
		"climate change", "global warming", "greenhouse gas", "carbon footprint", "pollution",
		"air quality", "water quality", "soil", "contamination", "toxic", "waste",
		"plastic", "recycling", "circular economy", "sustainability", "environmental impact",
		# Geographic features
		"fjord", "mountains", "valleys", "rivers", "lakes", "coastline", "archipelago",
		"wetlands", "tundra", "boreal", "arctic", "subarctic", "Nordic",
		# Norwegian nature
		"midnight sun", "northern lights", "aurora", "seasonal", "winter", "summer",
		"snow", "ice", "permafrost", "glacier", "watershed", "salmon", "cod",
		# Protection & restoration
		"protected area", "national park", "reserve", "restoration", "rewilding",
		"reforestation", "afforestation", "green corridor", "green space", "urban forest",
		# Environmental policy
		"environmental law", "regulation", "compliance", "monitoring", "assessment",
		"impact study", "sustainability report", "carbon tax", "cap and trade"
	],
	
	Domain.EQUITY: [
		# Justice & fairness
		"fair", "justice", "accessibility", "equality", "rights", "marginalized", "indigenous", "distribution",
		"equity", "fairness", "equal", "inclusive", "inclusion", "diversity", "representation",
		"discrimination", "bias", "prejudice", "privilege", "disadvantaged", "vulnerable",
		# Social justice
		"social justice", "human rights", "civil rights", "economic justice", "environmental justice",
		"gender equality", "racial equality", "LGBTQ+", "disability rights", "age discrimination",
		# Access & opportunity
		"access", "opportunity", "affordable", "available", "reachable", "barrier", "obstacle",
		"threshold", "entry point", "participation", "inclusion", "exclusion",
		# Economic equity
		"income", "wealth", "poverty", "inequality", "gap", "distribution", "redistribution",
		"minimum wage", "living wage", "universal basic income", "welfare", "benefits",
		"affordable housing", "gentrification", "displacement", "cost of living",
		# Norwegian context
		"Sami rights", "indigenous rights", "minority rights", "immigrant integration",
		"asylum seekers", "refugees", "multicultural", "intercultural", "integration",
		# Energy equity
		"energy poverty", "energy justice", "energy access", "energy burden", "energy democracy",
		"just transition", "green jobs", "reskilling", "retraining", "worker protection",
		# Procedural equity
		"participation", "consultation", "representation", "voice", "agency", "empowerment",
		"decision-making", "governance", "transparency", "accountability"
	]
}

# For tracking conversation flow
var message_history = []
var last_update_time = 0
var update_interval = 1 # Update metrics every 3 messages

func _ready():
	 #Initialize with slightly different starting values to make meter more interesting
	metrics[Domain.ENERGY] = 0.1
	metrics[Domain.COMMUNITY] = 0.15
	metrics[Domain.INNOVATION] = 0.05
	metrics[Domain.ENVIRONMENT] = 0.1
	metrics[Domain.EQUITY] = 0.05
	
	#for domain in Domain.values():
		#metrics[domain] = 0.1  # Start with a small non-zero value

func analyze_message(sender: String, content: String) -> void:
	# Store message for context analysis
	message_history.append({"sender": sender, "content": content})
	
	# Limit history size
	if message_history.size() > 20:
		message_history.pop_front()
	
	# Update metrics only periodically to avoid excessive calculations
	if message_history.size() - last_update_time >= update_interval:
		_update_metrics()
		last_update_time = message_history.size()

func _update_metrics() -> void:
	# Prepare text for analysis
	print("SustainabilityTracker: Updating metrics")
	var recent_content = ""
	for i in range(max(0, message_history.size() - 5), message_history.size()):
		recent_content += message_history[i].content + " "
	
	# Calculate keyword matches for each domain
	var domain_scores = {}
	for domain in Domain.values():
		domain_scores[domain] = _calculate_domain_score(recent_content, domain)
	
	# Update metrics with smoothing
	for domain in Domain.values():
		metrics[domain] = metrics[domain] * 0.5 + domain_scores[domain] * 0.5
	
	print("SustainabilityTracker: New domain scores: ", domain_scores)
	print("SustainabilityTracker: Updated metrics: ", metrics)
	
	# Emit signal for UI updates
	emit_signal("metrics_updated", metrics)
	print("SustainabilityTracker: Emitted metrics_updated signal")

func _calculate_domain_score(content: String, domain: int) -> float:
	var score = 0.0
	var content_lower = content.to_lower()
	var total_words = content.split(" ").size()
	
	# Count keyword matches with different weights
	var matches_found = []
	for keyword in domain_keywords[domain]:
		var keyword_lower = keyword.to_lower()
		var matches = content_lower.count(keyword_lower)
		if matches > 0:
			matches_found.append({"keyword": keyword, "count": matches})
			
			# Base score per keyword match (reduced due to larger keyword set)
			var keyword_score = matches * 0.1
			
			# Bonus for longer, more specific keywords
			if keyword.length() > 10:
				keyword_score *= 1.5
			elif keyword.length() > 6:
				keyword_score *= 1.2
				
			# Bonus for compound terms (multiple words)
			if " " in keyword:
				keyword_score *= 1.3
				
			score += keyword_score
	
	# Apply contextual bonuses
	if score > 0:
		# Diversity bonus: reward using different types of keywords
		var unique_keywords = matches_found.size()
		if unique_keywords > 3:
			score *= 1.2
		elif unique_keywords > 1:
			score *= 1.1
		
		# Cross-domain sustainability thinking bonus
		var cross_domain_count = 0
		for other_domain in Domain.values():
			if other_domain != domain:
				for keyword in domain_keywords[other_domain]:
					if content_lower.count(keyword.to_lower()) > 0:
						cross_domain_count += 1
						break
		
		if cross_domain_count >= 2:
			score *= 1.4  # Strong cross-domain thinking
		elif cross_domain_count >= 1:
			score *= 1.2  # Some cross-domain thinking
		
		# Length-based normalization (prevent spam from overwhelming)
		if total_words > 0:
			var keyword_density = float(matches_found.size()) / float(total_words)
			if keyword_density > 0.3:  # Too keyword-heavy, reduce score
				score *= 0.8
	
	# Debug output for testing
	if matches_found.size() > 0:
		print("SustainabilityTracker: Domain ", Domain.keys()[domain], " found keywords: ", matches_found)
	
	return min(score, 1.0)  # Cap at 1.0

func get_metrics() -> Dictionary:
	return metrics.duplicate()

func get_overall_sustainability_score() -> float:
	var total = 0.0
	for domain in metrics:
		total += metrics[domain]
	return total / metrics.size()

func get_domain_feedback() -> Dictionary:
	var feedback = {}
	for domain in Domain.values():
		if metrics[domain] < 0.3:
			feedback[domain] = "Consider exploring " + Domain.keys()[domain].to_lower().capitalize() + " topics more"
	return feedback
