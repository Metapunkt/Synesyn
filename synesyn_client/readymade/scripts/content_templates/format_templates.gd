@tool
extends Resource
class_name FormatTemplates
## Format-specific content templates for optimized output generation

# Template definitions for different content formats
static var format_templates = {
	"Video": {
		"structure": ["hook", "introduction", "main_content", "call_to_action"],
		"prompts": {
			"hook": "Create a compelling 5-second hook that immediately grabs attention. Focus on curiosity, urgency, or surprise.",
			"introduction": "Write a 15-second introduction that establishes credibility and previews value.",
			"main_content": "Develop the core content with visual storytelling in mind. Include specific examples and actionable insights.",
			"call_to_action": "End with a clear, specific action for viewers to take next."
		},
		"optimization": {
			"max_length": 2000,
			"visual_cues": true,
			"pacing_notes": true,
			"thumbnail_suggestions": true
		}
	},
	
	"Article": {
		"structure": ["headline", "introduction", "body_sections", "conclusion"],
		"prompts": {
			"headline": "Create a compelling headline that promises specific value and includes relevant keywords.",
			"introduction": "Write an introduction that hooks readers and clearly states what they'll learn.",
			"body_sections": "Develop 3-5 main sections with subheadings, examples, and actionable insights.",
			"conclusion": "Summarize key points and provide clear next steps or call-to-action."
		},
		"optimization": {
			"seo_friendly": true,
			"readability_score": "8th grade",
			"keyword_density": "1-2%",
			"meta_description": true
		}
	},
	
	"Carousel": {
		"structure": ["slide_1_hook", "slide_2_problem", "slide_3_solution", "slide_4_benefit", "slide_5_cta"],
		"prompts": {
			"slide_1_hook": "Create a bold statement or question that stops scrolling. Maximum 10 words.",
			"slide_2_problem": "Identify the specific problem your audience faces. Be relatable and specific.",
			"slide_3_solution": "Present your solution clearly and concisely. Focus on the 'how'.",
			"slide_4_benefit": "Highlight the transformation or outcome. Make it tangible and desirable.",
			"slide_5_cta": "End with a clear action step. Tell them exactly what to do next."
		},
		"optimization": {
			"slides_count": 5,
			"text_per_slide": 20,
			"visual_hierarchy": true,
			"swipe_momentum": true
		}
	},
	
	"Infographic": {
		"structure": ["title", "key_stats", "process_steps", "visual_elements"],
		"prompts": {
			"title": "Create a clear, benefit-focused title that explains the infographic's value.",
			"key_stats": "Include 3-5 compelling statistics that support your main message.",
			"process_steps": "Break down complex information into 5-7 digestible steps or points.",
			"visual_elements": "Suggest icons, charts, and visual metaphors that enhance understanding."
		},
		"optimization": {
			"data_visualization": true,
			"scannable_layout": true,
			"brand_consistency": true,
			"shareability": true
		}
	},
	
	"Podcast": {
		"structure": ["intro_teaser", "main_segments", "guest_interaction", "wrap_up"],
		"prompts": {
			"intro_teaser": "Create a 30-second teaser that previews the most valuable insights from the episode.",
			"main_segments": "Develop 3-4 main talking points with natural conversation flow and storytelling.",
			"guest_interaction": "Include thoughtful questions and discussion points if featuring guests.",
			"wrap_up": "Summarize key takeaways and preview next episode or related content."
		},
		"optimization": {
			"conversational_tone": true,
			"episode_length": "20-45 minutes",
			"show_notes": true,
			"timestamp_markers": true
		}
	},
	
	"Live Stream": {
		"structure": ["pre_stream_setup", "opening_engagement", "content_delivery", "audience_interaction"],
		"prompts": {
			"pre_stream_setup": "Plan technical setup, key talking points, and engagement hooks.",
			"opening_engagement": "Start with energy and immediately engage viewers who join.",
			"content_delivery": "Present content in digestible chunks with regular interaction breaks.",
			"audience_interaction": "Include polls, Q&A segments, and real-time response to comments."
		},
		"optimization": {
			"real_time_engagement": true,
			"technical_quality": true,
			"audience_retention": true,
			"replay_value": true
		}
	},
	
	"Short Text": {
		"structure": ["hook_line", "value_proposition", "call_to_action"],
		"prompts": {
			"hook_line": "Start with a statement that immediately captures attention in 10 words or less.",
			"value_proposition": "Clearly state the benefit or insight in 1-2 sentences.",
			"call_to_action": "End with a specific action or thought-provoking question."
		},
		"optimization": {
			"character_limit": 280,
			"hashtag_strategy": true,
			"engagement_optimization": true,
			"shareability": true
		}
	},
	
	"Image(s)": {
		"structure": ["visual_concept", "text_overlay", "style_guide", "composition"],
		"prompts": {
			"visual_concept": "Describe the core visual metaphor or concept that represents the idea.",
			"text_overlay": "Create minimal, impactful text that enhances rather than overwhelms the visual.",
			"style_guide": "Specify colors, fonts, and visual style that aligns with brand and message.",
			"composition": "Describe layout, focal points, and visual hierarchy for maximum impact."
		},
		"optimization": {
			"visual_impact": true,
			"brand_consistency": true,
			"platform_specs": true,
			"accessibility": true
		}
	}
}

static func get_template(format: String) -> Dictionary:
	"""Get template configuration for specific format"""
	return format_templates.get(format, {})

static func get_format_prompt(format: String, section: String = "") -> String:
	"""Get specific prompt for format and section"""
	var template = get_template(format)
	if section.is_empty():
		return _build_complete_format_prompt(format, template)
	else:
		return template.get("prompts", {}).get(section, "")

static func _build_complete_format_prompt(format: String, template: Dictionary) -> String:
	"""Build complete prompt for format including all sections"""
	var prompt = "FORMAT: %s\n\n" % format
	
	var structure = template.get("structure", [])
	var prompts = template.get("prompts", {})
	var optimization = template.get("optimization", {})
	
	prompt += "CONTENT STRUCTURE:\n"
	for i in range(structure.size()):
		var section = structure[i]
		var section_prompt = prompts.get(section, "")
		prompt += "%d. %s: %s\n" % [i + 1, section.capitalize(), section_prompt]
	
	prompt += "\nOPTIMIZATION REQUIREMENTS:\n"
	for key in optimization.keys():
		var value = optimization[key]
		prompt += "- %s: %s\n" % [key.capitalize().replace("_", " "), str(value)]
	
	return prompt

static func get_all_formats() -> Array[String]:
	"""Get list of all available formats"""
	return format_templates.keys()

static func apply_format_optimization(content: String, format: String) -> Dictionary:
	"""Apply format-specific optimization and return analysis"""
	var template = get_template(format)
	var optimization = template.get("optimization", {})
	var analysis = {
		"format": format,
		"optimized": true,
		"suggestions": [],
		"metrics": {}
	}
	
	# Apply format-specific analysis
	match format:
		"Video":
			analysis.metrics["estimated_length"] = content.length() / 150.0  # ~150 words per minute
			if content.length() > optimization.get("max_length", 2000):
				analysis.suggestions.append("Content may be too long for optimal video engagement")
		
		"Article":
			var word_count = content.split(" ").size()
			analysis.metrics["word_count"] = word_count
			analysis.metrics["estimated_read_time"] = word_count / 200.0  # ~200 words per minute
			if word_count < 300:
				analysis.suggestions.append("Article may be too short for SEO optimization")
		
		"Carousel":
			var slides = content.split("\n\n")
			analysis.metrics["slide_count"] = slides.size()
			if slides.size() != optimization.get("slides_count", 5):
				analysis.suggestions.append("Optimize for %d slides for best engagement" % optimization.get("slides_count", 5))
		
		"Short Text":
			analysis.metrics["character_count"] = content.length()
			var char_limit = optimization.get("character_limit", 280)
			if content.length() > char_limit:
				analysis.suggestions.append("Content exceeds %d character limit" % char_limit)
	
	return analysis 