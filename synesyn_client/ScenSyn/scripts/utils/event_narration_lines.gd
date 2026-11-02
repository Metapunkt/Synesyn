extends Resource
class_name EventNarrationLines

# Dictionary: event_id -> Array of possible narration lines
var lines := {
	"POWER_FAIL": [
		"The lights flicker and the room falls silent as the power fails.",
		"Darkness sweeps over the city as the grid collapses, leaving only the hum of emergency lights.",
		"A sudden blackout plunges the group into uneasy silence.",
		"The conference room is bathed in shadows as the power cuts out unexpectedly.",
		"A hush falls as monitors and lights die, the crisis now all too real.",
		"The emergency generator sputters, casting eerie shadows on anxious faces.",
		"Someone fumbles for a flashlight as the room is swallowed by darkness.",
		"The hum of electronics ceases, replaced by nervous whispers.",
		"A cold chill settles in as the heating system shuts down.",
		"The cityscape outside vanishes, hidden behind a curtain of black."
	],
	"FIRE_ALARM": [
		"A shrill alarm pierces the air, signaling danger somewhere in the building.",
		"Red lights flash and a siren blares, sending a jolt of panic through the group.",
		"The fire alarm erupts, drowning out conversation and raising the stakes.",
		"An urgent alarm rings out, forcing everyone to pause and listen.",
		"A warning klaxon echoes, hinting at trouble nearby.",
		"The group scrambles for information as the alarm continues to blare.",
		"Evacuation instructions crackle over the intercom, adding to the confusion.",
		"Smoke is suspected, and tension spikes as everyone scans the exits.",
		"The alarm's relentless wail frays nerves and disrupts plans.",
		"A sense of urgency sweeps the room as the alarm persists."
	],
	"PLAYER_WIN": [
		"Cheers erupt as the group realizes they've overcome the crisis.",
		"Relief washes over the team as their efforts finally pay off.",
		"A sense of triumph fills the room as the solution is found.",
		"The group exchanges smiles, knowing they've averted disaster.",
		"Victory is palpable as the city lights up once more.",
		"Laughter and applause break out, echoing through the hall.",
		"A wave of accomplishment sweeps over everyone present.",
		"The team basks in the glow of their hard-won success.",
		"High-fives and congratulations are exchanged all around.",
		"The crisis fades into memory as celebration takes hold."
	],
	"PLAYER_LOSS": [
		"A heavy silence settles as the group faces the consequences of failure.",
		"Defeat hangs in the air, each member lost in their own thoughts.",
		"The crisis deepens, and hope seems to slip away.",
		"A somber mood overtakes the room as the outcome becomes clear.",
		"The group is left to ponder what went wrong.",
		"No one speaks as the weight of loss becomes apparent.",
		"A sense of regret lingers, impossible to shake.",
		"The team struggles to process the setback.",
		"A feeling of helplessness pervades the group.",
		"The silence is broken only by the sound of someone sighing."
	],
	"NEW_CHALLENGE": [
		"A new obstacle emerges, demanding the group's immediate attention.",
		"Fresh challenges arise, testing the resolve of everyone present.",
		"The situation shifts as another problem surfaces.",
		"A new dilemma is presented, complicating the path forward.",
		"Unexpected news forces the group to reconsider their plans.",
		"A sudden development throws previous strategies into question.",
		"The group must adapt quickly to face the latest hurdle.",
		"A curveball is thrown, catching everyone off guard.",
		"The stakes are raised as new complications unfold.",
		"A fresh crisis looms, demanding creative solutions."
	],
	"PLAYER_JOIN": [
		"A new face enters the room, bringing fresh perspective to the crisis.",
		"The group welcomes a new member, hopeful for new ideas.",
		"Someone new arrives, their presence shifting the group dynamic.",
		"A door opens and another joins the discussion.",
		"A newcomer steps in, ready to help tackle the challenges ahead.",
		"Introductions are made as the team expands.",
		"The group makes space for a new voice at the table.",
		"A sense of anticipation greets the latest arrival.",
		"Fresh energy enters the room with the new participant.",
		"The dynamic shifts as the group grows in number."
	],
	"PLAYER_LEAVE": [
		"A member quietly departs, leaving the group to press on.",
		"Someone exits, their absence felt by those who remain.",
		"A chair sits empty as one of the group leaves the room.",
		"The group is diminished as a participant steps away.",
		"A farewell is exchanged as a player leaves the crisis behind.",
		"The team pauses to acknowledge the departure.",
		"A sense of loss lingers as the door closes behind them.",
		"The group must adjust to the absence of a familiar voice.",
		"Plans are revised to account for the missing member.",
		"The atmosphere shifts as the group continues with one less."
	],
	"CRISIS_ESCALATES": [
		"Tension rises as the crisis takes a turn for the worse.",
		"The situation intensifies, putting everyone on edge.",
		"A new complication sends a ripple of anxiety through the group.",
		"The crisis deepens, demanding urgent action.",
		"Pressure mounts as the stakes grow higher.",
		"A sense of urgency grips the team as problems multiply.",
		"The group scrambles to keep up with the escalating situation.",
		"Every decision now carries greater risk.",
		"The mood darkens as the crisis spirals.",
		"A cascade of setbacks threatens to overwhelm the group."
	],
	"RESOURCE_FOUND": [
		"A valuable resource is discovered, offering a glimmer of hope.",
		"The group uncovers something that could turn the tide.",
		"A breakthrough is made as a new asset comes to light.",
		"Fortune smiles as a key resource is found.",
		"A discovery sparks renewed optimism among the group.",
		"The team celebrates a stroke of luck.",
		"A hidden cache is revealed, boosting morale.",
		"The group quickly devises plans to use the newfound asset.",
		"A sense of possibility returns as resources increase.",
		"The discovery is met with excitement and relief."
	],
	"RESOURCE_LOST": [
		"A critical resource slips from the group's grasp, complicating matters.",
		"The loss of an asset forces the team to rethink their strategy.",
		"A setback occurs as something important is lost.",
		"The group reels from the loss of a vital resource.",
		"A misstep results in a valuable asset being lost.",
		"The team scrambles to compensate for the loss.",
		"A sense of frustration grows as resources dwindle.",
		"The group must improvise in the face of scarcity.",
		"Plans are derailed by the unexpected loss.",
		"The setback tests the group's resilience."
	],
	"WEATHER_CHANGE": [
		"A sudden shift in the weather alters the mood in the room.",
		"Rain lashes against the windows, adding urgency to the discussion.",
		"A cold wind rattles the glass, making everyone shiver.",
		"Sunlight breaks through the clouds, offering a brief moment of hope.",
		"Thunder rumbles in the distance, underscoring the tension.",
		"Fog rolls in, blurring the cityscape outside.",
		"A rainbow appears, briefly lifting spirits.",
		"The temperature drops, and everyone pulls their coats tighter.",
		"Lightning flashes, illuminating worried faces.",
		"The sound of hail pelting the roof adds to the chaos."
	],
	"INFORMATION_LEAK": [
		"A confidential report is accidentally shared, causing a stir among the group.",
		"Sensitive information leaks, forcing the team to reconsider their strategy.",
		"Rumors begin to circulate, threatening to undermine trust.",
		"A slip of the tongue reveals more than intended.",
		"The group scrambles to contain the fallout from an unexpected leak.",
		"A document is found in the wrong hands, raising suspicions.",
		"The leak prompts a flurry of urgent messages.",
		"Trust is shaken as secrets come to light.",
		"The team debates how to handle the breach.",
		"A sense of vulnerability spreads as the news gets out."
	],
	"MEDIA_ATTENTION": [
		"News crews gather outside, their presence felt even within the meeting room.",
		"A journalist's question puts the group on the spot.",
		"Media coverage intensifies, raising the stakes for every decision.",
		"Cameras flash as the crisis draws public attention.",
		"A breaking news alert interrupts the proceedings.",
		"The group prepares for a press conference under pressure.",
		"Social media buzzes with speculation about the crisis.",
		"A reporter's microphone is thrust forward, seeking comment.",
		"The team debates how much to reveal to the public.",
		"A live broadcast captures the tension inside."
	],
	"SABOTAGE": [
		"Sabotage is suspected as systems begin to malfunction.",
		"A deliberate act of disruption throws plans into chaos.",
		"The group suspects foul play as setbacks mount.",
		"Security is tightened after evidence of tampering is found.",
		"A sense of paranoia spreads as sabotage is confirmed.",
		"A crucial system fails under mysterious circumstances.",
		"Saboteurs leave behind cryptic clues.",
		"The group launches an investigation into the cause.",
		"Trust erodes as accusations fly.",
		"The team works overtime to repair the damage."
	],
	"ALLY_SUPPORT": [
		"An unexpected ally offers support, boosting morale.",
		"Help arrives from a neighboring city, bringing new resources.",
		"A partner organization pledges assistance.",
		"The group receives a message of encouragement from outside.",
		"Reinforcements are promised, giving the team hope.",
		"A shipment of supplies is delivered just in time.",
		"A neighboring team shares valuable expertise.",
		"The group is heartened by a show of solidarity.",
		"A new partnership is forged in the heat of crisis.",
		"Supporters send words of encouragement from afar."
	],
	"CITIZEN_PROTEST": [
		"Chants from a protest outside filter into the room.",
		"Citizens gather, demanding action and accountability.",
		"A demonstration erupts, adding pressure to the group.",
		"The sound of a crowd grows louder, impossible to ignore.",
		"Placards and banners appear outside, signaling unrest.",
		"A spokesperson for the protesters requests a meeting.",
		"The group debates how to respond to public demands.",
		"Police presence increases as the protest swells.",
		"Media coverage of the protest intensifies scrutiny.",
		"The protestors' chants become a constant backdrop."
	],
	"SYSTEM_RESTORED": [
		"Power surges back, greeted by a collective sigh of relief.",
		"Systems reboot and lights flicker on, restoring order.",
		"The hum of machinery signals a return to normalcy.",
		"A cheer goes up as critical systems are restored.",
		"The group celebrates as the crisis abates, if only for a moment.",
		"Monitors blink to life, displaying reassuring data.",
		"The heating system kicks in, warming the chilled room.",
		"A sense of normalcy returns as routines resume.",
		"The team quickly checks for lingering issues.",
		"A round of applause greets the restoration of order."
	],
	"INTERNAL_CONFLICT": [
		"A heated argument breaks out, threatening group cohesion.",
		"Tensions flare as opinions clash.",
		"Disagreements escalate, making consensus elusive.",
		"A rift forms within the group, complicating decision-making.",
		"Voices are raised and tempers tested as conflict erupts.",
		"The facilitator calls for a break to cool tempers.",
		"A compromise is sought amid the discord.",
		"The group struggles to refocus on the task at hand.",
		"Personal grievances bubble to the surface.",
		"A mediator is called in to help resolve the dispute."
	],
	"MYSTERIOUS_EVENT": [
		"An unexplained phenomenon leaves the group baffled.",
		"Strange noises prompt uneasy glances around the room.",
		"A mysterious message appears, its meaning unclear.",
		"Lights flicker in a pattern no one can explain.",
		"A sense of the uncanny settles over the group.",
		"A shadow moves where no one is standing.",
		"Electronic devices behave unpredictably.",
		"A cryptic symbol is found on a whiteboard.",
		"The group debates possible explanations for the odd occurrence.",
		"A chill runs down everyone's spine as the event unfolds."
	],
	"MORALE_BOOST": [
		"A heartfelt speech lifts everyone's spirits.",
		"Someone cracks a joke, breaking the tension.",
		"A small victory is celebrated, however briefly.",
		"The group shares a moment of camaraderie.",
		"A gesture of kindness renews hope among the team.",
		"A round of coffee is passed around, lightening the mood.",
		"A team member shares an inspiring story.",
		"A spontaneous round of applause erupts.",
		"The group takes a moment to acknowledge their progress.",
		"A creative idea sparks excitement and renewed energy."
	],
	"STORY_STALL": [
		"The room grows quiet as the group hesitates, waiting for someone to act.",
		"Time seems to slow as indecision takes hold.",
		"With no clear direction, the crisis lingers unresolved.",
		"A sense of stagnation settles over the group, urging someone to break the silence.",
		"The narrator summarizes recent events, hoping to inspire action: {last_choice}",
		"The group exchanges uncertain glances, each waiting for another to speak.",
		"Momentum fades as the discussion stalls, the crisis unresolved.",
		"A heavy silence falls, broken only by the ticking of a distant clock.",
		"The narrator wonders aloud if anyone will take the initiative.",
		"The story pauses, inviting someone to step forward and lead."
	],
	"PROMPT_CHARACTER": [
		"{character_name}, what will you do next to address the crisis?",
		"All eyes turn to {character_name} for a decision.",
		"The group waits for {character_name} to respond to the challenge: {challenge}",
		"{character_name}, your input could change the course of events.",
		"The narrator prompts {character_name}: {challenge}",
		"{character_name}, the outcome may depend on your next move.",
		"A question hangs in the air for {character_name}: {challenge}",
		"The group looks to {character_name} for inspiration.",
		"{character_name}, will you rise to the occasion?",
		"The narrator addresses {character_name} directly, awaiting a response."
	],
	"SPOTLIGHT_DECISION": [
		"It's up to {character_name} to make a key decision now.",
		"The spotlight falls on {character_name}, who must choose the next step.",
		"Everyone looks to {character_name} for leadership.",
		"{character_name} faces a pivotal moment in the story.",
		"The group awaits {character_name}'s choice.",
		"All attention shifts to {character_name} as the next move is decided.",
		"{character_name} stands at a crossroads, the group's fate in their hands.",
		"A hush falls as {character_name} prepares to speak.",
		"The narrator highlights {character_name}'s role in the unfolding events.",
		"{character_name} is called upon to break the deadlock."
	],
	"SUSTAINABILITY_ALERT": [
		"As energy reserves drop to {energy_level}%, the group feels the pressure mount.",
		"Resource status is now '{resource_status}', forcing a change in strategy.",
		"The sustainability crisis deepens: energy at {energy_level}%, resources '{resource_status}'.",
		"The narrator warns: with only {energy_level}% energy left, every action counts.",
		"A sustainability alert: {resource_status} resources and {energy_level}% energy remain.",
		"The group must act quickly as sustainability indicators worsen.",
		"A warning light blinks: energy at {energy_level}%, resources '{resource_status}'.",
		"The city's future hangs in the balance as sustainability falters.",
		"The narrator urges caution: dwindling resources threaten the group's plans.",
		"A critical threshold is reached: {energy_level}% energy, resources '{resource_status}'."
	]
}

func get_random_line(event_id: String) -> String:
	if lines.has(event_id):
		var arr = lines[event_id]
		if arr.size() > 0:
			return arr[randi() % arr.size()]
	return "" 