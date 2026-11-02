extends BaseMetapromptManager
class_name SustainabilityMetapromptManager

## SustainabilityMetapromptManager - Sustainability-specific metaprompt management
##
## This class extends BaseMetapromptManager to provide sustainability-focused
## prompting, keyword analysis, and domain-specific narrative guidance.

# Sustainability-specific keywords for content analysis
var sustainability_keywords = {
	"energy": ["renewable", "solar", "wind", "efficiency", "grid", "consumption"],
	"community": ["local", "participation", "awareness", "education", "collaboration"],
	"innovation": ["technology", "research", "development", "smart solutions", "adaptation"],
	"environment": ["conservation", "biodiversity", "emissions", "climate change", "ecosystem"],
	"equity": ["fairness", "accessibility", "inclusivity", "social justice", "equal opportunity"]
}

# Sustainability concepts for advanced content detection
var sustainability_concepts = {
	"energy transition": "The shift from fossil fuels to renewable energy sources",
	"circular economy": "An economic system aimed at eliminating waste and the continual use of resources",
	"carbon footprint": "The total amount of greenhouse gases produced to directly and indirectly support human activities",
	"sustainable development": "Development that meets the needs of the present without compromising the ability of future generations to meet their own needs",
	"green infrastructure": "A network providing the 'ingredients' for solving urban and climatic challenges by building with nature"
}

func _ready():
	super._ready()
	game_theme = "Sustainability & Future Planning"

## Override: Get theme-specific keywords
func get_theme_keywords(_scenario: Dictionary) -> Dictionary:
	return sustainability_keywords

## Override: Get theme-specific concepts  
func get_theme_concepts(_scenario: Dictionary) -> Dictionary:
	return sustainability_concepts

## Override: Generate sustainability-focused game session metaprompt
func generate_game_session_metaprompt(scenario: Dictionary, characters: Array, player_character: Dictionary) -> String:
	var prompt = get_core_narrative_rules(player_character.get("name", "Player"))
	
	# Add sustainability-specific responsibilities
	prompt += """

### Sustainability Theme Responsibilities:
- Integrate sustainability challenges naturally into character dialogue and environmental events
- Present realistic trade-offs between economic, environmental, and social factors
- Ground discussions in near-future scenarios with current sustainability technologies
- Encourage collaborative problem-solving around sustainability dilemmas
- Maintain focus on practical, implementable solutions rather than abstract concepts

"""
	
	# Add scenario and character context
	prompt += get_scenario_context(scenario, characters, player_character)
	
	# Add sustainability-specific dialogue format
	prompt += get_sustainability_dialogue_format()
	
	# Add narrative phase guidance if available
	if StoryState and StoryState.has_method("get_current_narrative_phase"):
		var current_phase = StoryState.get_current_narrative_phase()
		var phase_instruction = get_phase_instruction(current_phase)
		if phase_instruction != "":
			prompt = phase_instruction + "\n\n" + prompt
	
	# Add current dilemmas if available
	if StoryState and StoryState.has_method("get_current_dilemmas"):
		var dilemmas = StoryState.get_current_dilemmas()
		if not dilemmas.is_empty():
			var knowledge_block = "\n\n## CURRENT ACTIONABLE DILEMMAS\n"
			knowledge_block += "The following specific problems have been identified. Ground your conversation and proposed actions in these concrete options.\n"
			for dilemma in dilemmas:
				knowledge_block += "- Problem: %s\n" % dilemma.get("problem", "Unknown Problem")
				var solutions = dilemma.get("solutions", [])
				for solution in solutions:
					knowledge_block += "  - Solution: %s (Benefit: %s, Risk: %s)\n" % [solution.get("name", "N/A"), solution.get("benefit", "N/A"), solution.get("risk", "N/A")]
			
			prompt += knowledge_block
	
	return prompt

## Get sustainability-specific dialogue format guidelines
func get_sustainability_dialogue_format() -> String:
	return """

## CHARACTER DIALOGUE FORMAT (CRITICAL)
**Format**: `**[Character Name]:** "Dialogue content"`
**NEVER** use narrator descriptions within dialogue blocks
**NEVER** add (gestures), *actions*, or descriptive text inside dialogue

### Sustainability Dialogue Guidelines:
- Characters should discuss sustainability topics as informed individuals, not experts
- Present multiple perspectives on sustainability challenges
- Include practical concerns (cost, implementation, social impact)
- Reference real-world sustainability technologies and approaches
- Encourage collaborative problem-solving and compromise
- Balance idealism with pragmatic constraints

### Character Voice Guidelines:
Each AI character should maintain consistent personality while engaging with sustainability themes:
- **Technical characters**: Focus on feasibility, implementation details, system design
- **Community representatives**: Emphasize social impact, equity, local concerns
- **Officials**: Balance policy implications, regulations, public interest
- **Activists**: Advocate for environmental protection while acknowledging trade-offs

"""

## Override: Inject sustainability focus into prompt based on metrics
func inject_theme_focus(prompt: String, intensity: String, feedback: Dictionary) -> String:
	var sustainability_instruction = "\n\nSUSTAINABILITY CONTEXT GUIDANCE: "
	
	if intensity == "low":
		sustainability_instruction += "Subtly weave sustainability themes into character dialogue and environmental descriptions. "
	elif intensity == "medium":
		sustainability_instruction += "Actively incorporate sustainability challenges into the narrative. Have characters discuss energy options, community impacts, or environmental concerns. "
	else: # high
		sustainability_instruction += "Make sustainability the central focus of this response. Introduce urgent sustainability challenges that require immediate attention and decision-making. "
		
	# Add specific guidance based on domain feedback
	if not feedback.is_empty():
		sustainability_instruction += "\n\nSPECIFIC FOCUS AREAS NEEDED: "
		for domain in feedback:
			match domain:
				0: # Energy
					sustainability_instruction += "Introduce energy-related challenges (power outages, renewable energy decisions, grid management). "
				1: # Community
					sustainability_instruction += "Show community perspectives, local concerns, or neighborhood-level sustainability initiatives. "
				2: # Innovation  
					sustainability_instruction += "Present new technologies, research developments, or innovative solutions for discussion. "
				3: # Environment
					sustainability_instruction += "Highlight environmental impacts, ecosystem concerns, or conservation opportunities. "
				4: # Equity
					sustainability_instruction += "Address social justice aspects, fair distribution of benefits/costs, or accessibility issues. "
		
	# Add Trondheim-specific context based on what's lacking
	if feedback.has(0): # Energy focus needed
		sustainability_instruction += "\n\nTRONDHEIM ENERGY CONTEXT: Consider the city's cold climate, district heating systems, and potential for hydro/wind power. "
	if feedback.has(1): # Community focus needed  
		sustainability_instruction += "\n\nTRONDHEIM COMMUNITY CONTEXT: Draw on Norwegian values of consensus-building, environmental stewardship, and social equality. "
	if feedback.has(2): # Innovation focus needed
		sustainability_instruction += "\n\nTRONDHEIM INNOVATION CONTEXT: Draw on NTNU's research capabilities and the city's tech-forward reputation. "
	
	# Insert the instruction before the final section of the prompt
	var final_section_pos = prompt.rfind("\nRemember")
	if final_section_pos > 0:
		prompt = prompt.left(final_section_pos) + sustainability_instruction + prompt.substr(final_section_pos)
	else:
		prompt += sustainability_instruction
	
	return prompt

## Override: Analyze sustainability content in message
func analyze_theme_content(message: String) -> Dictionary:
	var content_score = {}
	var lower_message = message.to_lower()
	
	for domain in sustainability_keywords:
		content_score[domain] = 0
		for keyword in sustainability_keywords[domain]:
			if keyword in lower_message:
				content_score[domain] += 1
	
	for concept in sustainability_concepts:
		if concept in lower_message:
			content_score["advanced_concepts"] = content_score.get("advanced_concepts", 0) + 1
	
	return content_score

## Override: Generate sustainability-specific challenge
func generate_theme_challenge(metrics: Dictionary) -> String:
	var challenges = [
		"A sudden power grid failure affects the district heating system, forcing immediate decisions about backup energy sources.",
		"New environmental regulations require rapid changes to current energy infrastructure, sparking community debate.",
		"A breakthrough in renewable technology offers opportunities but requires significant investment and social adaptation.",
		"Climate change impacts are accelerating, demanding urgent action on both mitigation and adaptation strategies.",
		"Social equity concerns arise as sustainability initiatives may disproportionately affect different community groups."
	]
	
	# Select challenge based on lowest-performing sustainability domain
	var lowest_domain = 0
	var lowest_score = 1.0
	
	for domain_id in metrics:
		if metrics[domain_id] < lowest_score:
			lowest_score = metrics[domain_id]
			lowest_domain = domain_id
	
	# Return domain-specific challenge or random if no clear lowest domain
	if lowest_domain < challenges.size():
		return challenges[lowest_domain]
	else:
		return challenges[randi() % challenges.size()]

## Override: Get sustainability-specific creative mission for narrative phase (PHASE 2)
func get_theme_creative_mission(phase: String, _scenario: Dictionary) -> String:
	match phase:
		"setup":
			return """
CREATIVE GOAL FOR SETUP PHASE:
Establish the sustainability crisis and stakeholder positions.
Success = Characters with DISTINCT perspectives on resource management emerge naturally.

- Make us CARE about the stakes through personal connections
- Make us WORRIED about what happens if crisis isn't addressed
- Show competing values (economic vs environmental vs social equity)
- Avoid lecture mode—reveal positions through character reactions
"""
		"incident":
			return """
CREATIVE GOAL FOR INCIDENT PHASE:
The sustainability crisis becomes immediate and unavoidable.
Success = A specific event forces choice between competing values.

- No more theoretical discussion—something happens NOW
- Force choice between legitimate but incompatible goods
- Show real consequences starting to unfold
- Characters must respond, not just debate
"""
		"rising":
			return """
CREATIVE GOAL FOR RISING ACTION PHASE:
Escalate tension through competing sustainability values.
Success = Characters forced to choose, trade-offs become stark.

- Avoid easy answers—every solution has costs
- Show what's sacrificed for each choice
- Personal stakes increase (affects characters directly)
- Alliances form and break based on priorities
"""
		"climax":
			return """
CREATIVE GOAL FOR CLIMAX PHASE:
The moment of decisive action on sustainability.
Success = One character (or coalition) commits to a path that changes everything.

- Be bold—this is the turning point
- Make it matter—consequences are significant
- Someone must take the leap, not just vote
- Show courage or cowardice in the moment
"""
		"resolution":
			return """
CREATIVE GOAL FOR RESOLUTION PHASE:
Face consequences of the sustainability decision made.
Success = Honest reflection on what was gained and what was sacrificed.

- Show both wins and losses
- Avoid propaganda—complexity matters
- Characters reflect on whether it was worth it
- Leave resonance, not just conclusion
"""
		"ended":
			return """
NARRATIVE PHASE: ENDED
The story has concluded. Provide final reflections and closure.
"""
		_:
			return ""
