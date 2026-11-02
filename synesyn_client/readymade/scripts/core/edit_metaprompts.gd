extends Node

## ReadyMade Edit Metaprompts System - Provides specialized prompts for different editing modes
## This singleton manages metaprompt templates for document editing workflows

# Edit mode metaprompt templates
var edit_mode_metaprompts: Dictionary = {
	"developmental": {
		"name": "Developmental Editing",
		"description": "Focus on big-picture elements: structure, pacing, character development, plot consistency",
		"system_prompt": """You are a developmental editor helping to improve the overall structure and content of a document. 

Your focus areas include:
- Overall structure and organization
- Flow and pacing of ideas
- Character development (for narrative content)
- Plot consistency and logical progression
- Content gaps or redundancies
- Audience appropriateness and engagement
- Major structural improvements

When providing feedback:
1. Focus on big-picture issues rather than line-level corrections
2. Suggest structural improvements and reorganization
3. Identify content that needs expansion or reduction
4. Consider the target audience and purpose
5. Provide actionable suggestions for improvement
6. Be constructive and encouraging

Current editing mode: DEVELOPMENTAL EDITING""",
		"context_template": """Document Context:
Title: {document_name}
Word Count: {word_count}
Edit Mode: Developmental Editing

{document_context}

Selected Text for Review:
{selected_text}

Context Around Selection:
{selection_context}"""
	},
	
	"structural": {
		"name": "Structural Editing",
		"description": "Focus on organization, flow, transitions, and logical sequence",
		"system_prompt": """You are a structural editor focused on improving the organization and flow of content.

Your focus areas include:
- Logical sequence and organization of ideas
- Transitions between sections and paragraphs
- Information hierarchy and structure
- Consistency in formatting and style
- Section balance and proportion
- Navigation and readability
- Coherence and cohesion

When providing feedback:
1. Analyze the logical flow of information
2. Suggest better organization or restructuring
3. Improve transitions and connections
4. Ensure consistent structural elements
5. Address any structural inconsistencies
6. Consider reader navigation and comprehension

Current editing mode: STRUCTURAL EDITING""",
		"context_template": """Document Context:
Title: {document_name}
Word Count: {word_count}
Edit Mode: Structural Editing

Document Structure Overview:
{document_context}

Section Under Review:
{selected_text}

Surrounding Context:
{selection_context}"""
	},
	
	"content": {
		"name": "Content Editing",
		"description": "Focus on clarity, accuracy, completeness, and factual correctness",
		"system_prompt": """You are a content editor focused on improving clarity, accuracy, and completeness of information.

Your focus areas include:
- Factual accuracy and verification
- Clarity and comprehensibility
- Completeness of information
- Logical consistency
- Evidence and support for claims
- Appropriate level of detail
- Content relevance and value

When providing feedback:
1. Check for factual accuracy and consistency
2. Improve clarity and comprehensibility
3. Identify missing or incomplete information
4. Strengthen arguments with better evidence
5. Remove irrelevant or redundant content
6. Ensure appropriate depth and detail
7. Verify claims and statements

Current editing mode: CONTENT EDITING""",
		"context_template": """Document Context:
Title: {document_name}
Word Count: {word_count}
Edit Mode: Content Editing

Content for Review:
{selected_text}

Document Context:
{document_context}

Surrounding Information:
{selection_context}"""
	},
	
	"line": {
		"name": "Line Editing",
		"description": "Focus on sentence structure, word choice, style, and readability",
		"system_prompt": """You are a line editor focused on improving sentence-level writing quality.

Your focus areas include:
- Sentence structure and variety
- Word choice and precision
- Style consistency and voice
- Rhythm and flow
- Conciseness and clarity
- Tone appropriateness
- Readability improvements

When providing feedback:
1. Improve sentence structure and variety
2. Suggest better word choices and phrasing
3. Ensure consistent style and tone
4. Eliminate wordiness and redundancy
5. Enhance rhythm and readability
6. Strengthen the author's voice
7. Make language more precise and engaging

Current editing mode: LINE EDITING""",
		"context_template": """Document Context:
Title: {document_name}
Word Count: {word_count}
Edit Mode: Line Editing

Text for Line Editing:
{selected_text}

Context:
{selection_context}

Document Overview:
{document_context}"""
	},
	
	"copy": {
		"name": "Copy Editing",
		"description": "Focus on grammar, punctuation, spelling, and mechanical correctness",
		"system_prompt": """You are a copy editor focused on correcting grammar, punctuation, spelling, and mechanical errors.

Your focus areas include:
- Grammar and syntax corrections
- Punctuation accuracy
- Spelling and typographical errors
- Capitalization consistency
- Number and date formatting
- Citation and reference formatting
- Style guide compliance

When providing feedback:
1. Correct all grammatical errors
2. Fix punctuation and capitalization issues
3. Identify and correct spelling mistakes
4. Ensure consistent formatting
5. Check number and date styles
6. Verify citation accuracy
7. Apply style guide rules consistently

Current editing mode: COPY EDITING""",
		"context_template": """Document Context:
Title: {document_name}
Word Count: {word_count}
Edit Mode: Copy Editing

Text for Copy Editing:
{selected_text}

Context for Reference:
{selection_context}"""
	},
	
	"proofreading": {
		"name": "Proofreading",
		"description": "Final review for typos, formatting issues, and minor errors",
		"system_prompt": """You are a proofreader conducting the final review before publication.

Your focus areas include:
- Final typo detection
- Formatting consistency
- Layout and appearance issues
- Final punctuation check
- Minor word corrections
- Consistency in style elements
- Final quality assurance

When providing feedback:
1. Catch any remaining typos or errors
2. Check formatting consistency
3. Verify style element consistency
4. Note any layout or appearance issues
5. Perform final punctuation review
6. Ensure professional presentation
7. Provide final quality approval

Current editing mode: PROOFREADING""",
		"context_template": """Document Context:
Title: {document_name}
Word Count: {word_count}
Edit Mode: Proofreading

Text for Final Review:
{selected_text}

Context:
{selection_context}

Final Check Focus: Typos, formatting, minor errors"""
	}
}

func _ready():
	print("EditMetaprompts: System ready with %d edit modes" % edit_mode_metaprompts.size())

func get_available_edit_modes() -> Array[String]:
	"""Get list of available edit modes"""
	return edit_mode_metaprompts.keys()

func get_edit_mode_info(mode: String) -> Dictionary:
	"""Get information about a specific edit mode"""
	if mode in edit_mode_metaprompts:
		return edit_mode_metaprompts[mode].duplicate()
	return {}

func get_edit_prompt(mode: String, context: Dictionary, user_prompt: String = "") -> String:
	"""Generate a complete editing prompt for the specified mode and context"""
	if not mode in edit_mode_metaprompts:
		push_error("EditMetaprompts: Unknown edit mode: " + mode)
		return ""
	
	var mode_data = edit_mode_metaprompts[mode]
	var system_prompt = mode_data.system_prompt
	
	# **NEW**: Enhance system prompt based on current work mode
	system_prompt += _get_work_mode_enhancement(mode)
	
	# Enhance system prompt for multi-document context
	if context.get("context_type") == "multi_document":
		system_prompt += _get_multi_document_enhancement(mode)
	
	# Build context section
	var context_prompt = _build_context_prompt(mode, context)
	
	# Build user request section
	var user_section = ""
	if not user_prompt.is_empty():
		user_section = "\n\nUser Request:\n" + user_prompt
	
	# Combine all parts
	var full_prompt = system_prompt + "\n\n" + context_prompt + user_section
	
	# Add closing instructions (now mode-aware)
	full_prompt += _get_closing_instructions(mode)
	
	return full_prompt

func get_multi_document_edit_prompt(mode: String, multi_context: Dictionary, user_prompt: String = "") -> String:
	"""Generate an editing prompt specifically for multi-document sessions"""
	if not mode in edit_mode_metaprompts:
		push_error("EditMetaprompts: Unknown edit mode: " + mode)
		return ""
	
	var mode_data = edit_mode_metaprompts[mode]
	var system_prompt = mode_data.system_prompt
	
	# **NEW**: Add work mode specific instructions
	system_prompt += _get_work_mode_enhancement(mode)
	
	# Add multi-document specific instructions
	system_prompt += _get_multi_document_enhancement(mode)
	
	# Build multi-document context
	var context_prompt = _build_multi_document_context_prompt(mode, multi_context)
	
	# Build user request section
	var user_section = ""
	if not user_prompt.is_empty():
		user_section = "\n\nUser Request:\n" + user_prompt
	
	# Combine all parts
	var full_prompt = system_prompt + "\n\n" + context_prompt + user_section
	
	# Add multi-document specific closing instructions (now mode-aware)
	full_prompt += _get_multi_document_closing_instructions(mode)
	
	return full_prompt

func _get_multi_document_enhancement(mode: String) -> String:
	"""Get mode-specific enhancements for multi-document editing"""
	var base_enhancement = """

**MULTI-DOCUMENT SESSION ACTIVE**
You are working with multiple related documents in this session. Consider:
- Consistency across all documents
- Cross-references and connections between documents
- Shared themes, terminology, and style
- Document relationships and dependencies
"""
	
	var mode_specific_enhancements = {
		"developmental": """
- Overall narrative or argument flow across documents
- Character or concept development consistency
- Structural alignment between related documents
- Content gaps that span multiple documents""",
		
		"structural": """
- Organizational consistency across documents
- Cross-document navigation and references
- Hierarchical alignment of information
- Structural patterns and conventions""",
		
		"content": """
- Factual consistency across all documents
- Terminology and definition alignment
- Cross-document fact-checking and verification
- Content completeness across the document set""",
		
		"line": """
- Voice and tone consistency across documents
- Style guide compliance across all texts
- Language patterns and word choice alignment
- Readability consistency between documents""",
		
		"copy": """
- Grammar and style rule consistency
- Formatting standardization across documents
- Citation and reference style alignment
- Mechanical consistency (punctuation, capitalization)""",
		
		"proofreading": """
- Final consistency check across all documents
- Cross-document formatting verification
- Style element standardization
- Final quality assurance for the complete document set"""
	}
	
	return base_enhancement + mode_specific_enhancements.get(mode, "")

func _get_work_mode_enhancement(edit_mode: String) -> String:
	"""Get work mode-specific editing enhancements based on current ModeManager setting"""
	# Check if ModeManager is available
	if not ModeManager:
		return ""
	
	var current_work_mode = ModeManager.get_current_mode()
	var mode_config: Variant = ModeManager.get_current_config()
	if mode_config == null:
		return ""
	
	print("EditMetaprompts: Integrating work mode '%s' with edit mode '%s'" % [current_work_mode, edit_mode])
	
	# Base work mode context
	var work_mode_context = """

**WORK MODE: %s**
%s

Target Formats: %s
Target Channels: %s
""" % [mode_config.name, mode_config.ai_prompt_prefix, ", ".join(mode_config.formats), ", ".join(mode_config.channels)]
	
	# Get mode-specific editing enhancements
	var enhancement = _get_mode_specific_editing_guidance(current_work_mode, edit_mode)
	
	return work_mode_context + enhancement

func _get_mode_specific_editing_guidance(work_mode: String, edit_mode: String) -> String:
	"""Get specific editing guidance based on work mode + edit mode combination"""
	
	# Social Media Mode Enhancements
	if work_mode == "social_media":
		var social_media_guidance = {
			"developmental": """
**SOCIAL MEDIA DEVELOPMENTAL EDITING:**
- Structure content for platform-specific attention spans
- Develop engaging hooks and calls-to-action
- Optimize content flow for scroll-based consumption
- Consider viral potential and shareability factors
- Develop content series and recurring themes
- Plan for multi-platform content adaptation""",
			
			"structural": """
**SOCIAL MEDIA STRUCTURAL EDITING:**
- Organize content with scannable formatting (bullet points, emojis)
- Structure for mobile-first consumption
- Create logical progression for carousel posts or threads
- Optimize information hierarchy for quick consumption
- Balance text, visual, and interactive elements
- Ensure cross-platform structural consistency""",
			
			"content": """
**SOCIAL MEDIA CONTENT EDITING:**
- Verify platform-specific best practices and trends
- Ensure content aligns with platform algorithms
- Check hashtag relevance and effectiveness
- Validate claims with credible, shareable sources
- Optimize content for target audience engagement
- Ensure brand voice consistency across platforms""",
			
			"line": """
**SOCIAL MEDIA LINE EDITING:**
- Optimize for platform character limits and formatting
- Create punchy, engaging sentence structures
- Use platform-appropriate language and tone
- Incorporate trending language and phrases naturally
- Balance casual and professional tone based on platform
- Optimize readability for mobile screens""",
			
			"copy": """
**SOCIAL MEDIA COPY EDITING:**
- Check platform-specific formatting requirements
- Verify hashtag spelling and trending status
- Ensure proper @mentions and tagging
- Check link formatting and functionality
- Verify emoji usage and platform compatibility
- Standardize brand voice across all platforms""",
			
			"proofreading": """
**SOCIAL MEDIA PROOFREADING:**
- Final check for platform-specific requirements
- Verify visual element placement and quality
- Check posting time optimization
- Ensure compliance with platform policies
- Final engagement optimization review
- Cross-platform consistency verification"""
		}
		return social_media_guidance.get(edit_mode, "")
	
	# Creative Writing Mode Enhancements
	elif work_mode == "creative_writing":
		var creative_writing_guidance = {
			"developmental": """
**CREATIVE WRITING DEVELOPMENTAL EDITING:**
- Develop compelling character arcs and motivations
- Strengthen plot structure and pacing
- Enhance thematic depth and resonance
- Develop authentic dialogue and voice
- Build immersive world-building elements
- Create emotional connection with readers""",
			
			"structural": """
**CREATIVE WRITING STRUCTURAL EDITING:**
- Optimize chapter and scene organization
- Improve transitions between scenes and chapters
- Balance narrative pacing and tension
- Structure flashbacks and time shifts effectively
- Organize multiple plotlines and subplots
- Create compelling story progression""",
			
			"content": """
**CREATIVE WRITING CONTENT EDITING:**
- Verify character consistency and development
- Check plot logic and continuity
- Enhance descriptive passages and settings
- Strengthen dialogue authenticity
- Develop sensory details and atmosphere
- Ensure thematic coherence throughout""",
			
			"line": """
**CREATIVE WRITING LINE EDITING:**
- Refine prose style and voice consistency
- Enhance rhythm and flow of sentences
- Strengthen imagery and metaphorical language
- Improve dialogue naturalness and distinctiveness
- Eliminate redundant or weak language
- Enhance emotional impact through word choice""",
			
			"copy": """
**CREATIVE WRITING COPY EDITING:**
- Check grammar while preserving authorial voice
- Verify dialogue punctuation and formatting
- Ensure consistent point of view
- Check tense consistency throughout
- Verify proper manuscript formatting
- Maintain genre-appropriate language conventions""",
			
			"proofreading": """
**CREATIVE WRITING PROOFREADING:**
- Final typo and error detection
- Verify character name consistency
- Check chapter numbering and formatting
- Ensure proper manuscript presentation
- Final style and voice consistency check
- Prepare for publication or submission standards"""
		}
		return creative_writing_guidance.get(edit_mode, "")
	
	# Academic Writing Mode Enhancements
	elif work_mode == "academic_writing":
		var academic_writing_guidance = {
			"developmental": """
**ACADEMIC WRITING DEVELOPMENTAL EDITING:**
- Strengthen argument structure and logical flow
- Develop comprehensive literature review integration
- Enhance theoretical framework presentation
- Improve methodology explanation and justification
- Strengthen conclusion and implications
- Develop scholarly contribution and originality""",
			
			"structural": """
**ACADEMIC WRITING STRUCTURAL EDITING:**
- Organize according to academic conventions
- Improve section and subsection organization
- Enhance logical progression of arguments
- Optimize citation placement and integration
- Balance theoretical and empirical content
- Create clear academic narrative structure""",
			
			"content": """
**ACADEMIC WRITING CONTENT EDITING:**
- Verify accuracy of citations and references
- Check factual accuracy and current research
- Strengthen evidence-based arguments
- Ensure comprehensive literature coverage
- Verify methodology appropriateness
- Check data presentation and interpretation""",
			
			"line": """
**ACADEMIC WRITING LINE EDITING:**
- Maintain scholarly tone and voice
- Improve clarity without sacrificing precision
- Enhance sentence variety and complexity
- Eliminate jargon where unnecessary
- Strengthen transitions between ideas
- Balance formal and accessible language""",
			
			"copy": """
**ACADEMIC WRITING COPY EDITING:**
- Verify citation format consistency (APA, MLA, etc.)
- Check academic style guide compliance
- Ensure proper formatting of references
- Verify technical terminology accuracy
- Check figure and table formatting
- Ensure consistent academic conventions""",
			
			"proofreading": """
**ACADEMIC WRITING PROOFREADING:**
- Final citation and reference verification
- Check journal or publication requirements
- Verify abstract and keyword accuracy
- Final formatting and style compliance
- Check supplementary materials
- Ensure professional academic presentation"""
		}
		return academic_writing_guidance.get(edit_mode, "")
	
	# Default case (unknown work mode)
	return ""

func _build_multi_document_context_prompt(_mode: String, context: Dictionary) -> String:
	"""Build context prompt for multi-document sessions"""
	var prompt = "MULTI-DOCUMENT EDITING SESSION\n"
	prompt += "==================================\n\n"
	
	# Session overview
	var session_info = context.get("session_summary", {})
	prompt += "Session Overview:\n"
	prompt += "- Total Documents: %d\n" % session_info.get("document_count", 0)
	prompt += "- Total Words: %d\n" % session_info.get("total_words", 0)
	prompt += "- Edit Mode: %s\n\n" % session_info.get("edit_mode", "unknown")
	
	# Primary document
	var primary_doc = context.get("primary_document")
	if primary_doc:
		prompt += "PRIMARY DOCUMENT (Main Focus):\n"
		prompt += "Title: %s\n" % primary_doc.get("name", "Unknown")
		prompt += "Word Count: %d\n" % primary_doc.get("word_count", 0)
		prompt += "Preview:\n%s\n\n" % primary_doc.get("preview", "No preview available")
	
	# Additional documents
	var additional_docs = context.get("additional_documents", [])
	if additional_docs.size() > 0:
		prompt += "SUPPORTING DOCUMENTS:\n"
		for i in range(additional_docs.size()):
			var doc = additional_docs[i]
			prompt += "%d. %s (%d words)\n" % [i + 1, doc.get("name", "Unknown"), doc.get("word_count", 0)]
			prompt += "   Preview: %s\n" % doc.get("preview", "No preview available")
			if doc.has("has_changes") and doc.has_changes:
				prompt += "   Status: Has unsaved changes\n"
			prompt += "\n"
	
	# Document relationships
	var relationships = context.get("relationships", [])
	if relationships.size() > 0:
		prompt += "DOCUMENT RELATIONSHIPS:\n"
		for relationship in relationships:
			prompt += "- %s ↔ %s: %s (%.1f%% similarity)\n" % [
				relationship.get("doc1_name", "Unknown"),
				relationship.get("doc2_name", "Unknown"),
				relationship.get("relationship_type", "unknown"),
				relationship.get("similarity", 0.0) * 100
			]
			
			var keywords = relationship.get("common_keywords", [])
			if keywords.size() > 0:
				prompt += "  Common themes: %s\n" % ", ".join(keywords.slice(0, 5))
		prompt += "\n"
	
	# Current selection context (if any)
	var selected_text = context.get("selected_text", "")
	if not selected_text.is_empty() and selected_text != "[No text selected - reviewing entire document or providing general guidance]":
		prompt += "CURRENT SELECTION (from primary document):\n"
		prompt += "%s\n\n" % selected_text
		
		var selection_context = context.get("selection_context", "")
		if not selection_context.is_empty():
			prompt += "SELECTION CONTEXT:\n"
			prompt += "%s\n\n" % selection_context
	
	return prompt

func _get_multi_document_closing_instructions(mode: String) -> String:
	"""Get closing instructions specific to multi-document editing (now work mode-aware)"""
	var base_instructions = """

MULTI-DOCUMENT EDITING GUIDELINES:
1. Consider the impact of changes across all related documents
2. Maintain consistency in style, tone, and terminology
3. Identify cross-document dependencies and relationships
4. Suggest improvements that benefit the entire document set
5. Flag inconsistencies between related documents
6. Prioritize changes that enhance overall coherence

Focus on both individual document quality and cross-document harmony."""
	
	var mode_specific = {
		"developmental": "\n\nFor multi-document developmental editing, pay special attention to overarching narrative structure, character/concept consistency, and thematic alignment across all documents.",
		"structural": "\n\nFor multi-document structural editing, ensure organizational patterns are consistent and cross-references work properly across the document set.",
		"content": "\n\nFor multi-document content editing, verify factual consistency and terminology alignment across all documents in the session.",
		"line": "\n\nFor multi-document line editing, maintain consistent voice, style, and readability standards across all documents.",
		"copy": "\n\nFor multi-document copy editing, apply grammar and style rules consistently across all documents and ensure formatting standardization.",
		"proofreading": "\n\nFor multi-document proofreading, perform final consistency checks across the entire document set and ensure professional presentation standards."
	}
	
	# Add work mode-specific multi-document instructions
	var work_mode_multi_doc_closing = _get_work_mode_multi_document_closing()
	
	return base_instructions + mode_specific.get(mode, "") + work_mode_multi_doc_closing

func _get_work_mode_multi_document_closing() -> String:
	"""Get work mode-specific multi-document closing instructions"""
	if not ModeManager:
		return ""
	
	var current_work_mode = ModeManager.get_current_mode()
	
	var multi_doc_work_mode_instructions = {
		"social_media": """

**MULTI-DOCUMENT SOCIAL MEDIA REMINDERS:**
- Ensure consistent brand voice across all platforms/content
- Check cross-platform content adaptation strategies
- Verify hashtag and mention consistency across documents
- Consider content sequencing and campaign flow
- Maintain platform-specific optimization across all content""",
		
		"creative_writing": """

**MULTI-DOCUMENT CREATIVE WRITING REMINDERS:**
- Maintain character voice consistency across all documents
- Verify timeline and world-building consistency
- Check narrative flow between related documents
- Ensure thematic coherence across the entire work
- Preserve authorial voice throughout all documents""",
		
		"academic_writing": """

**MULTI-DOCUMENT ACADEMIC WRITING REMINDERS:**
- Verify citation consistency and completeness across all documents
- Check argument flow and logical consistency across papers
- Ensure terminology and definitions align across documents
- Maintain scholarly rigor throughout the document set
- Verify cross-references and internal consistency"""
	}
	
	return multi_doc_work_mode_instructions.get(current_work_mode, "")

func _build_context_prompt(mode: String, context: Dictionary) -> String:
	"""Build the context section of the prompt"""
	var mode_data = edit_mode_metaprompts[mode]
	var template = mode_data.context_template
	
	# Default values
	var document_name = context.get("document_name", "Untitled Document")
	var word_count = context.get("word_count", 0)
	var selected_text = context.get("selected_text", "")
	var selection_context = context.get("selection_context", "")
	var document_context = context.get("document_context", "")
	
	# Handle missing selected text
	if selected_text.is_empty():
		selected_text = "[No text selected - reviewing entire document or providing general guidance]"
	
	if selection_context.is_empty():
		selection_context = "[No additional context available]"
	
	if document_context.is_empty():
		document_context = "[Document context not available]"
	
	# Format the template
	var formatted_context = template.format({
		"document_name": document_name,
		"word_count": str(word_count),
		"selected_text": selected_text,
		"selection_context": selection_context,
		"document_context": document_context
	})
	
	return formatted_context

func _get_closing_instructions(mode: String) -> String:
	"""Get mode-specific closing instructions (now includes work mode awareness)"""
	var base_instructions = """

Please provide your editing suggestions in a clear, actionable format. Include:
1. Specific issues identified
2. Suggested improvements
3. Reasoning for changes
4. Priority level (if multiple issues)

Focus on the most important improvements for this editing pass."""
	
	var mode_specific = {
		"developmental": "\n\nRemember: Focus on big-picture structural and content issues rather than line-level details.",
		"structural": "\n\nRemember: Focus on organization, flow, and logical structure rather than specific wording.",
		"content": "\n\nRemember: Focus on accuracy, clarity, and completeness of information.",
		"line": "\n\nRemember: Focus on sentence-level improvements in style, word choice, and readability.",
		"copy": "\n\nRemember: Focus on mechanical correctness - grammar, punctuation, and spelling.",
		"proofreading": "\n\nRemember: This is the final pass - focus on catching any remaining errors and ensuring polish."
	}
	
	# Add work mode-specific closing instructions
	var work_mode_closing = _get_work_mode_closing_instructions()
	
	return base_instructions + mode_specific.get(mode, "") + work_mode_closing

func _get_work_mode_closing_instructions() -> String:
	"""Get work mode-specific closing instructions"""
	if not ModeManager:
		return ""
	
	var current_work_mode = ModeManager.get_current_mode()
	var _mode_config = ModeManager.get_current_config()
	
	var work_mode_instructions = {
		"social_media": """

**SOCIAL MEDIA MODE REMINDERS:**
- Keep platform character limits in mind
- Suggest engaging, shareable improvements
- Consider visual element integration
- Optimize for mobile consumption
- Focus on audience engagement potential""",
		
		"creative_writing": """

**CREATIVE WRITING MODE REMINDERS:**
- Preserve and enhance the author's unique voice
- Consider emotional impact and reader experience
- Suggest improvements that strengthen storytelling
- Balance technical correction with creative flow
- Focus on narrative effectiveness""",
		
		"academic_writing": """

**ACADEMIC WRITING MODE REMINDERS:**
- Maintain scholarly rigor and formal tone
- Verify citation accuracy and completeness
- Suggest improvements that strengthen argumentation
- Consider peer review and publication standards
- Focus on clarity without sacrificing precision"""
	}
	
	return work_mode_instructions.get(current_work_mode, "")

func get_mode_description(mode: String) -> String:
	"""Get the description for a specific edit mode"""
	if mode in edit_mode_metaprompts:
		return edit_mode_metaprompts[mode].description
	return "Unknown edit mode"

func get_mode_display_name(mode: String) -> String:
	"""Get the display name for a specific edit mode"""
	if mode in edit_mode_metaprompts:
		return edit_mode_metaprompts[mode].name
	return mode.capitalize()

func validate_context(_context: Dictionary) -> bool:
	"""Validate that context contains required fields"""
	# Context is flexible - we can work with whatever is provided
	return true

func get_context_template_for_mode(mode: String) -> String:
	"""Get the context template for a specific mode"""
	if mode in edit_mode_metaprompts:
		return edit_mode_metaprompts[mode].context_template
	return ""

func create_context_from_document(document, selected_text: String = "", selection_context: String = "") -> Dictionary:
	"""Create a context dictionary from a DocumentContext object"""
	if not document:
		return {}
	
	return {
		"document_name": document.file_name,
		"word_count": document.word_count,
		"selected_text": selected_text,
		"selection_context": selection_context,
		"document_context": _create_document_summary(document)
	}

func create_multi_document_context(primary_document, additional_documents: Array = [], selected_text: String = "", selection_context: String = "") -> Dictionary:
	"""Create a context dictionary for multi-document sessions"""
	if not primary_document:
		return {}
	
	var context = {
		"document_name": primary_document.file_name,
		"word_count": primary_document.word_count,
		"selected_text": selected_text,
		"selection_context": selection_context,
		"document_context": _create_multi_document_summary(primary_document, additional_documents),
		"is_multi_document": true,
		"additional_document_count": additional_documents.size()
	}
	
	return context

func _create_multi_document_summary(primary_document, additional_documents: Array) -> String:
	"""Create a summary that includes multiple documents"""
	var summary = "=== PRIMARY DOCUMENT ===\n"
	summary += _create_document_summary(primary_document)
	
	if additional_documents.size() > 0:
		summary += "\n\n=== ADDITIONAL DOCUMENTS ===\n"
		for i in range(additional_documents.size()):
			var doc = additional_documents[i]
			summary += "\n--- Document %d: %s ---\n" % [i + 1, doc.name]
			summary += "Word Count: %d\n" % doc.word_count
			summary += "Preview: %s\n" % doc.content_preview
			if doc.has("relationship_to_primary"):
				summary += "Relationship to Primary: %s\n" % doc.relationship_to_primary
	
	return summary

func get_enhanced_edit_prompt(mode: String, document_context: Dictionary, selected_text: String = "", selection_context: String = "", user_prompt: String = "") -> String:
	"""Generate an enhanced editing prompt that works with multi-document contexts"""
	if not mode in edit_mode_metaprompts:
		push_error("EditMetaprompts: Unknown edit mode: " + mode)
		return ""
	
	# Build context from DocumentSessionManager context if available
	var context = {}
	if document_context.has("context_type") and document_context.context_type == "multi_document":
		context = _build_multi_document_context(document_context, selected_text, selection_context)
	else:
		# Single document context
		if document_context.has("primary_document") and document_context.primary_document:
			var primary = document_context.primary_document
			context = {
				"document_name": primary.name,
				"word_count": primary.word_count,
				"selected_text": selected_text,
				"selection_context": selection_context,
				"document_context": "Document: %s (%d words)" % [primary.name, primary.word_count]
			}
		else:
			# Fallback to basic context
			context = {
				"document_name": "Current Document",
				"word_count": 0,
				"selected_text": selected_text,
				"selection_context": selection_context,
				"document_context": "Context not available"
			}
	
	return get_edit_prompt(mode, context, user_prompt)

func _build_multi_document_context(document_context: Dictionary, selected_text: String, selection_context: String) -> Dictionary:
	"""Build context dictionary from multi-document session context"""
	var primary = document_context.get("primary_document", {})
	var supporting = document_context.get("supporting_documents", [])
	
	var context_text = ""
	if not primary.is_empty():
		context_text += "=== PRIMARY DOCUMENT ===\n"
		context_text += "Name: %s\n" % primary.get("name", "Unknown")
		context_text += "Word Count: %d\n" % primary.get("word_count", 0)
		context_text += "Preview: %s\n" % primary.get("content_preview", "No preview available")
	
	if supporting.size() > 0:
		context_text += "\n=== SUPPORTING DOCUMENTS ===\n"
		for i in range(supporting.size()):
			var doc = supporting[i]
			context_text += "\nDocument %d: %s\n" % [i + 1, doc.get("name", "Unknown")]
			context_text += "Word Count: %d\n" % doc.get("word_count", 0)
			context_text += "Preview: %s\n" % doc.get("content_preview", "No preview")
			context_text += "Relationship: %s\n" % doc.get("relationship_to_primary", "unknown")
	
	return {
		"document_name": primary.get("name", "Multi-Document Session"),
		"word_count": primary.get("word_count", 0),
		"selected_text": selected_text,
		"selection_context": selection_context,
		"document_context": context_text,
		"is_multi_document": true
	}

func get_context_aware_prompt(mode: String, selected_text: String = "", selection_context: String = "", user_prompt: String = "") -> String:
	"""Get a context-aware prompt that automatically uses the current document session"""
	if not DocumentSessionManager:
		# Fallback to basic prompt
		var basic_context = {
			"document_name": "Current Document",
			"word_count": 0,
			"selected_text": selected_text,
			"selection_context": selection_context,
			"document_context": "Document context not available"
		}
		return get_edit_prompt(mode, basic_context, user_prompt)
	
	# Get context from DocumentSessionManager
	var session_context = DocumentSessionManager.get_document_context_for_llm(true)  # Include all documents
	return get_enhanced_edit_prompt(mode, session_context, selected_text, selection_context, user_prompt)

func get_mode_specific_multi_document_guidance(mode: String) -> String:
	"""Get mode-specific guidance for multi-document editing"""
	var guidance = {
		"developmental": """
Multi-Document Developmental Editing:
- Consider how documents work together as a cohesive whole
- Look for consistency in themes, tone, and messaging across documents
- Identify opportunities to strengthen connections between documents
- Ensure each document serves its purpose within the larger work""",
		
		"structural": """
Multi-Document Structural Editing:
- Analyze the logical flow between documents
- Check for consistent organization patterns
- Ensure smooth transitions when documents are meant to be read together
- Verify that each document's structure supports the overall architecture""",
		
		"content": """
Multi-Document Content Editing:
- Cross-reference facts and information between documents
- Identify and resolve contradictions or inconsistencies
- Look for opportunities to eliminate redundancy across documents
- Ensure each document adds unique value to the collection""",
		
		"line": """
Multi-Document Line Editing:
- Maintain consistent voice and style across all documents
- Look for opportunities to improve transitions between documents
- Ensure terminology is used consistently throughout
- Consider how sentence variety works across the document set""",
		
		"copy": """
Multi-Document Copy Editing:
- Apply consistent style guide rules across all documents
- Check for consistent formatting and presentation
- Verify that references and citations are uniform
- Ensure consistent spelling and capitalization choices""",
		
		"proofreading": """
Multi-Document Proofreading:
- Perform final consistency check across all documents
- Verify that formatting is uniform throughout
- Check that any cross-references between documents are accurate
- Ensure professional presentation of the complete document set"""
	}
	
	return guidance.get(mode, "Multi-document editing guidance not available for this mode.")

func enhance_prompt_with_multi_document_guidance(base_prompt: String, mode: String, is_multi_document: bool) -> String:
	"""Enhance a prompt with multi-document specific guidance"""
	if not is_multi_document:
		return base_prompt
	
	var guidance = get_mode_specific_multi_document_guidance(mode)
	return base_prompt + "\n\n" + guidance

func _create_document_summary(document) -> String:
	"""Create a summary of the document for context"""
	var summary = "Document: %s\n" % document.file_name
	summary += "Word Count: %d\n" % document.word_count
	summary += "Last Modified: %s\n" % Time.get_datetime_string_from_unix_time(document.last_modified)
	
	if document.has_unsaved_changes():
		summary += "Status: Has unsaved changes\n"
	
	if document.edit_history.size() > 0:
		summary += "Recent Changes: %d edits made\n" % document.edit_history.size()
	
	# Add first few lines of content as preview
	var lines = document.content.split("\n", false, 5)
	if lines.size() > 0:
		summary += "\nDocument Preview:\n"
		for i in range(min(3, lines.size())):
			summary += lines[i] + "\n"
		if lines.size() > 3:
			summary += "...\n"
	
	return summary

func get_edit_mode_priorities() -> Dictionary:
	"""Get the typical priority order for edit modes in a workflow"""
	return {
		"developmental": 1,  # First - big picture
		"structural": 2,     # Second - organization  
		"content": 3,        # Third - accuracy and clarity
		"line": 4,          # Fourth - sentence level
		"copy": 5,          # Fifth - grammar and mechanics
		"proofreading": 6   # Last - final polish
	}

func get_suggested_workflow() -> Array[String]:
	"""Get suggested order of editing modes for a complete workflow"""
	return ["developmental", "structural", "content", "line", "copy", "proofreading"] 
