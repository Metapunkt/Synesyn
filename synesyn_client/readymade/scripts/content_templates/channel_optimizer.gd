@tool
extends Resource
class_name ChannelOptimizer
## Channel-specific content optimization for different social media platforms

# Platform-specific optimization rules and guidelines
static var channel_configs = {
	"YouTube": {
		"content_style": "educational_entertainment",
		"optimal_length": {"min": 8, "max": 15, "unit": "minutes"},
		"audience_behavior": "deep_engagement",
		"algorithm_factors": ["watch_time", "engagement_rate", "click_through_rate"],
		"content_guidelines": {
			"hook_duration": 15,  # seconds
			"thumbnail_importance": "critical",
			"title_length": {"min": 60, "max": 70, "unit": "characters"},
			"description_length": {"min": 125, "max": 200, "unit": "words"},
			"call_to_action": "subscribe_and_comment"
		},
		"optimization_prompts": {
			"title": "Create a YouTube title that includes keywords, promises value, and creates curiosity. Use numbers, power words, and emotional triggers.",
			"thumbnail": "Design a thumbnail with high contrast, clear focal point, and minimal text. Use bright colors and expressive faces when relevant.",
			"description": "Write a description that includes keywords in the first 125 characters, provides value preview, and includes relevant timestamps.",
			"engagement": "Include questions, polls, and direct viewer engagement throughout the content."
		}
	},
	
	"Instagram": {
		"content_style": "visual_storytelling",
		"optimal_length": {"min": 30, "max": 90, "unit": "seconds"},
		"audience_behavior": "quick_consumption",
		"algorithm_factors": ["engagement_rate", "saves", "shares", "time_spent"],
		"content_guidelines": {
			"hook_duration": 3,  # seconds
			"visual_quality": "critical",
			"caption_length": {"min": 150, "max": 300, "unit": "characters"},
			"hashtag_count": {"min": 5, "max": 10},
			"story_integration": "recommended"
		},
		"optimization_prompts": {
			"visual": "Create visually stunning content with strong composition, good lighting, and brand-consistent aesthetics.",
			"caption": "Write captions that tell a story, ask questions, and encourage saves and shares. Use line breaks for readability.",
			"hashtags": "Use a mix of broad and niche hashtags relevant to your content and audience.",
			"engagement": "Post when your audience is most active and respond to comments quickly."
		}
	},
	
	"TikTok": {
		"content_style": "trend_driven_entertainment",
		"optimal_length": {"min": 15, "max": 60, "unit": "seconds"},
		"audience_behavior": "rapid_scrolling",
		"algorithm_factors": ["completion_rate", "engagement_rate", "shares"],
		"content_guidelines": {
			"hook_duration": 1,  # seconds
			"trend_relevance": "critical",
			"music_importance": "high",
			"text_overlay": "minimal_but_effective",
			"vertical_format": "required"
		},
		"optimization_prompts": {
			"hook": "Start with immediate visual or auditory impact. First second determines everything.",
			"trends": "Incorporate current trends, sounds, or challenges while maintaining your message.",
			"pacing": "Keep fast pacing with quick cuts and dynamic movement to maintain attention.",
			"authenticity": "Be genuine and relatable. TikTok audiences value authenticity over polish."
		}
	},
	
	"Facebook": {
		"content_style": "community_focused",
		"optimal_length": {"min": 3, "max": 5, "unit": "minutes"},
		"audience_behavior": "social_sharing",
		"algorithm_factors": ["meaningful_interactions", "time_spent", "shares"],
		"content_guidelines": {
			"community_focus": "high",
			"discussion_starter": "important",
			"native_video": "preferred",
			"caption_length": {"min": 100, "max": 200, "unit": "words"}
		},
		"optimization_prompts": {
			"community": "Create content that brings people together and encourages meaningful discussion.",
			"shareability": "Make content that people want to share with friends and family.",
			"native_posting": "Upload videos directly to Facebook rather than sharing from other platforms.",
			"timing": "Post when your specific audience is online, typically evenings and weekends."
		}
	},
	
	"Twitter/X": {
		"content_style": "conversational_insights",
		"optimal_length": {"min": 1, "max": 3, "unit": "tweets"},
		"audience_behavior": "real_time_engagement",
		"algorithm_factors": ["engagement_rate", "retweets", "replies"],
		"content_guidelines": {
			"character_limit": 280,
			"thread_potential": "high",
			"hashtag_count": {"min": 1, "max": 3},
			"real_time_relevance": "important"
		},
		"optimization_prompts": {
			"brevity": "Communicate complex ideas in simple, punchy language.",
			"threads": "Break longer content into engaging thread format with numbered tweets.",
			"timing": "Tweet when current events or trends make your content most relevant.",
			"engagement": "Ask questions and respond to replies to build conversation."
		}
	},
	
	"LinkedIn": {
		"content_style": "professional_insights",
		"optimal_length": {"min": 5, "max": 10, "unit": "minutes"},
		"audience_behavior": "professional_learning",
		"algorithm_factors": ["engagement_quality", "professional_relevance", "shares"],
		"content_guidelines": {
			"professional_tone": "required",
			"industry_relevance": "critical",
			"thought_leadership": "valued",
			"post_length": {"min": 150, "max": 300, "unit": "words"}
		},
		"optimization_prompts": {
			"authority": "Position yourself as a thought leader with unique insights and experience.",
			"value": "Provide actionable professional advice and industry insights.",
			"networking": "Encourage professional discussion and connection building.",
			"credibility": "Back up claims with data, examples, and professional experience."
		}
	},
	
	"Discord": {
		"content_style": "community_conversation",
		"optimal_length": {"min": 2, "max": 10, "unit": "messages"},
		"audience_behavior": "active_participation",
		"algorithm_factors": ["message_engagement", "thread_participation"],
		"content_guidelines": {
			"conversational_tone": "required",
			"community_specific": "critical",
			"real_time_interaction": "expected",
			"multimedia_support": "available"
		},
		"optimization_prompts": {
			"community": "Tailor content to the specific Discord community's interests and culture.",
			"interaction": "Encourage back-and-forth conversation and community participation.",
			"timing": "Be present and responsive during peak community hours.",
			"value": "Provide immediate value through help, insights, or entertainment."
		}
	}
}

static func get_channel_config(channel: String) -> Dictionary:
	"""Get configuration for specific channel"""
	return channel_configs.get(channel, {})

static func optimize_for_channel(content: String, channel: String, _format: String = "") -> Dictionary:
	"""Optimize content for specific channel and return recommendations"""
	var config = get_channel_config(channel)
	var optimization = {
		"channel": channel,
		"original_content": content,
		"optimized_content": content,
		"recommendations": [],
		"metrics": {},
		"channel_specific_additions": {}
	}
	
	if config.is_empty():
		optimization.recommendations.append("Channel configuration not found - using generic optimization")
		return optimization
	
	# Apply channel-specific optimizations
	match channel:
		"YouTube":
			optimization = _optimize_for_youtube(content, config, optimization)
		"Instagram":
			optimization = _optimize_for_instagram(content, config, optimization)
		"TikTok":
			optimization = _optimize_for_tiktok(content, config, optimization)
		"Facebook":
			optimization = _optimize_for_facebook(content, config, optimization)
		"Twitter/X":
			optimization = _optimize_for_twitter(content, config, optimization)
		"LinkedIn":
			optimization = _optimize_for_linkedin(content, config, optimization)
		"Discord":
			optimization = _optimize_for_discord(content, config, optimization)
	
	return optimization

static func _optimize_for_youtube(content: String, config: Dictionary, optimization: Dictionary) -> Dictionary:
	"""YouTube-specific optimization"""
	var word_count = content.split(" ").size()
	var estimated_duration = word_count / 150.0  # ~150 words per minute
	
	optimization.metrics["estimated_duration"] = estimated_duration
	optimization.metrics["word_count"] = word_count
	
	# Check optimal length
	var optimal = config.get("optimal_length", {})
	if estimated_duration < optimal.get("min", 8):
		optimization.recommendations.append("Content may be too short for YouTube algorithm optimization (aim for 8+ minutes)")
	elif estimated_duration > optimal.get("max", 15):
		optimization.recommendations.append("Content may be too long - consider breaking into multiple videos")
	
	# Add YouTube-specific elements
	optimization.channel_specific_additions = {
		"suggested_title": "Create compelling title with keywords and emotional triggers",
		"thumbnail_concept": "Design high-contrast thumbnail with clear focal point",
		"description_template": "Include keywords in first 125 characters, add timestamps",
		"end_screen_cta": "Subscribe, like, and check out related videos",
		"community_engagement": "Ask viewers to comment with their thoughts or experiences"
	}
	
	return optimization

static func _optimize_for_instagram(content: String, config: Dictionary, optimization: Dictionary) -> Dictionary:
	"""Instagram-specific optimization"""
	var char_count = content.length()
	
	optimization.metrics["character_count"] = char_count
	optimization.metrics["estimated_read_time"] = char_count / 200.0  # ~200 chars per second
	
	# Check caption length
	var guidelines = config.get("content_guidelines", {})
	var caption_length = guidelines.get("caption_length", {})
	if char_count > caption_length.get("max", 300):
		optimization.recommendations.append("Caption may be too long for Instagram - consider shortening or using carousel format")
	
	# Add Instagram-specific elements
	optimization.channel_specific_additions = {
		"visual_requirements": "High-quality, well-lit, aesthetically pleasing imagery",
		"caption_structure": "Hook + Story + Call-to-action with line breaks",
		"hashtag_strategy": "Mix of 5-10 relevant hashtags (broad + niche)",
		"story_integration": "Create complementary Instagram Story content",
		"engagement_tactics": "Ask questions, use polls, encourage saves"
	}
	
	return optimization

static func _optimize_for_tiktok(content: String, config: Dictionary, optimization: Dictionary) -> Dictionary:
	"""TikTok-specific optimization"""
	var word_count = content.split(" ").size()
	var estimated_duration = word_count / 180.0  # Faster pace for TikTok
	
	optimization.metrics["estimated_duration"] = estimated_duration
	optimization.metrics["word_count"] = word_count
	
	# Check optimal length
	var optimal = config.get("optimal_length", {})
	if estimated_duration > optimal.get("max", 60):
		optimization.recommendations.append("Content too long for TikTok - aim for 15-60 seconds")
	
	# Add TikTok-specific elements
	optimization.channel_specific_additions = {
		"hook_strategy": "Immediate visual/auditory impact in first second",
		"trend_integration": "Incorporate current sounds, effects, or challenges",
		"pacing_notes": "Fast cuts, dynamic movement, keep viewers engaged",
		"text_overlay": "Minimal but strategic text overlays for key points",
		"authenticity_focus": "Be genuine and relatable over polished perfection"
	}
	
	return optimization

static func _optimize_for_linkedin(content: String, config: Dictionary, optimization: Dictionary) -> Dictionary:
	"""LinkedIn-specific optimization"""
	var word_count = content.split(" ").size()
	
	optimization.metrics["word_count"] = word_count
	optimization.metrics["professional_tone_score"] = _analyze_professional_tone(content)
	
	# Check post length
	var guidelines = config.get("content_guidelines", {})
	var post_length = guidelines.get("post_length", {})
	if word_count < post_length.get("min", 150):
		optimization.recommendations.append("Post may be too short for LinkedIn engagement")
	elif word_count > post_length.get("max", 300):
		optimization.recommendations.append("Consider breaking into multiple posts or using LinkedIn article format")
	
	# Add LinkedIn-specific elements
	optimization.channel_specific_additions = {
		"professional_positioning": "Establish thought leadership and expertise",
		"industry_relevance": "Connect content to current industry trends and challenges",
		"networking_angle": "Encourage professional discussion and connections",
		"credibility_markers": "Include relevant experience, data, and examples",
		"call_to_action": "Invite professional discussion and knowledge sharing"
	}
	
	return optimization

static func _optimize_for_twitter(content: String, _config: Dictionary, optimization: Dictionary) -> Dictionary:
	"""Twitter/X-specific optimization"""
	var char_count = content.length()
	var thread_potential = char_count > 280
	
	optimization.metrics["character_count"] = char_count
	optimization.metrics["thread_required"] = thread_potential
	
	if thread_potential:
		var thread_count = (char_count / 250) + 1  # ~250 chars per tweet for readability
		optimization.metrics["suggested_thread_length"] = thread_count
		optimization.recommendations.append("Content should be formatted as %d-tweet thread" % thread_count)
	
	# Add Twitter-specific elements
	optimization.channel_specific_additions = {
		"brevity_focus": "Communicate complex ideas in simple, punchy language",
		"thread_structure": "Number tweets and use hooks to maintain engagement",
		"hashtag_strategy": "Use 1-3 relevant hashtags maximum",
		"timing_considerations": "Tweet when content is most relevant to current events",
		"engagement_tactics": "Ask questions and encourage retweets and replies"
	}
	
	return optimization

static func _optimize_for_facebook(content: String, _config: Dictionary, optimization: Dictionary) -> Dictionary:
	"""Facebook-specific optimization"""
	var word_count = content.split(" ").size()
	
	optimization.metrics["word_count"] = word_count
	optimization.metrics["shareability_score"] = _analyze_shareability(content)
	
	# Add Facebook-specific elements
	optimization.channel_specific_additions = {
		"community_focus": "Create content that brings people together",
		"shareability_factors": "Make content people want to share with friends/family",
		"native_video_preference": "Upload videos directly to Facebook",
		"discussion_starters": "Include questions that encourage meaningful conversation",
		"timing_strategy": "Post during peak family/social hours"
	}
	
	return optimization

static func _optimize_for_discord(content: String, _config: Dictionary, optimization: Dictionary) -> Dictionary:
	"""Discord-specific optimization"""
	var message_count = content.split("\n").size()
	
	optimization.metrics["message_count"] = message_count
	optimization.metrics["conversation_potential"] = _analyze_conversation_potential(content)
	
	# Add Discord-specific elements
	optimization.channel_specific_additions = {
		"community_tailoring": "Adapt to specific Discord community culture",
		"real_time_interaction": "Be present for immediate responses and engagement",
		"multimedia_integration": "Use images, gifs, and reactions effectively",
		"conversation_starters": "Include elements that encourage back-and-forth discussion",
		"community_value": "Provide immediate help, insights, or entertainment"
	}
	
	return optimization

static func _analyze_professional_tone(content: String) -> float:
	"""Analyze how professional the content tone is (0-100)"""
	var professional_keywords = ["strategy", "insights", "experience", "industry", "professional", "business", "leadership", "expertise"]
	var casual_keywords = ["awesome", "cool", "guys", "hey", "lol", "omg"]
	
	var professional_count = 0
	var casual_count = 0
	var content_lower = content.to_lower()
	
	for keyword in professional_keywords:
		if keyword in content_lower:
			professional_count += 1
	
	for keyword in casual_keywords:
		if keyword in content_lower:
			casual_count += 1
	
	var total_indicators = professional_count + casual_count
	if total_indicators == 0:
		return 50.0  # Neutral
	
	return (float(professional_count) / float(total_indicators)) * 100.0

static func _analyze_shareability(content: String) -> float:
	"""Analyze how shareable the content is (0-100)"""
	var shareable_elements = ["surprising", "helpful", "funny", "inspiring", "shocking", "useful", "amazing", "incredible"]
	var content_lower = content.to_lower()
	var score = 0.0
	
	for element in shareable_elements:
		if element in content_lower:
			score += 12.5  # Each element adds to shareability
	
	return min(100.0, score)

static func _analyze_conversation_potential(content: String) -> float:
	"""Analyze how likely content is to start conversations (0-100)"""
	var conversation_starters = ["what do you think", "question", "opinion", "experience", "thoughts", "?"]
	var content_lower = content.to_lower()
	var score = 0.0
	
	for starter in conversation_starters:
		if starter in content_lower:
			score += 16.7  # Each element adds to conversation potential
	
	return min(100.0, score)

static func get_multi_channel_strategy(channels: Array[String], content: String, format: String = "") -> Dictionary:
	"""Create optimization strategy for multiple channels"""
	var strategy = {
		"base_content": content,
		"format": format,
		"channels": {},
		"cross_platform_recommendations": []
	}
	
	# Optimize for each channel
	for channel in channels:
		strategy.channels[channel] = optimize_for_channel(content, channel, format)
	
	# Add cross-platform recommendations
	if "YouTube" in channels and "TikTok" in channels:
		strategy.cross_platform_recommendations.append("Create short TikTok teasers from YouTube content highlights")
	
	if "Instagram" in channels and "LinkedIn" in channels:
		strategy.cross_platform_recommendations.append("Adapt Instagram visuals with professional captions for LinkedIn")
	
	if "Twitter/X" in channels:
		strategy.cross_platform_recommendations.append("Use Twitter for real-time engagement and driving traffic to other platforms")
	
	return strategy 
