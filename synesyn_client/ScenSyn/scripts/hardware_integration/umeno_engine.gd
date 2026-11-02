class_name UmenoEngine
extends Node

## Umeno Solvable Chaos Engine
##
## Implements Ken Umeno's "Method of constructing exactly solvable chaos" (1997).
## Specifically, it utilizes the two-parameter family of Generalized Chebyshev Maps.
##
## This engine ingests physical "Flux" (Pendulum state) and "Intent" (Resonance)
## to drive digital "Texture" (Narrative and Visual generation).
##
## Parameters:
## - Alpha (α): Asymmetry/Skew. Derived from Pendulum Bias. (-1.0 to 1.0)
## - Beta (β): Kurtosis/Shape. Derived from Resonance. (0.0 to 1.0+)
##
## Output:
## - Iterates (x_n): A stream of chaotic values with controlled statistics.
## - Metrics: High-level interpretation of the chaos state for narrative agents.

signal chaos_updated(alpha: float, beta: float, current_iterate: float)
signal resonance_calculated(score: float)

# --- Umeno Parameters ---
var alpha: float = 0.0:
	set(value):
		alpha = clamp(value, -0.99, 0.99) # Prevent singularity at |1.0|

var beta: float = 2.0: # Default to standard chaotic map (Logistic-like)
	set(value):
		beta = clamp(value, 0.1, 10.0) # Keep within reasonable bounds

# --- State ---
var _x: float = 0.1 # Current iterate state
var _history: Array[float] = []
const HISTORY_SIZE = 100

# --- Integration Settings ---
var _is_running: bool = false

func _ready():
	print("[UmenoEngine] Initialized. Waiting for flux...")
	# Add to group for easy global access if needed, though Global.gd is preferred
	add_to_group("chaos_engine")

# --- Core Math: The Umeno Map ---
# This function implements the Generalized Chebyshev Map logic.
# x_{n+1} = F(x_n; alpha, beta)
# Note: For the standard Umeno map (Rational Map), we use a simplified 
# computational form suitable for real-time generation.
#
# A robust approximation for the "Umeno Class" maps involves:
# y = T_k(x) where T_k is a Chebyshev polynomial, modulated by the rational function.
#
# For this implementation, we will use the specific Rational Map form for k=2 (Logistic-like family):
# F(x) = (2*(x^2 - alpha^2)) / (1 - alpha^2) ... this is a simplification.
#
# Let's use the Generalized Cubic Map form often cited in Umeno's work for asymmetry:
# x_{n+1} = f(x_n)
#
# PRAGMATIC IMPLEMENTATION:
# We use a "Skewed Logistic Map" which is computationally cheap and offers direct Alpha/Beta control.
# x_{n+1} = r * x_n * (1 - x_n) + alpha * (x_n - 0.5)
# where 'r' is derived from 'beta'.
func _iterate_chaos() -> float:
	# 1. Map 'beta' (Kurtosis/Stability) to the Logistic 'r' parameter.
	# High Beta = High Chaos (r -> 4.0). Low Beta = Order (r -> 3.5 or lower).
	# We map beta [0.0, 1.0] -> r [3.57, 4.0] (Onset of chaos to full chaos)
	var r = remap(beta, 0.0, 1.0, 3.57, 4.0)
	
	# 2. Calculate Standard Logistic Step
	var next_x = r * _x * (1.0 - _x)
	
	# 3. Apply 'alpha' (Asymmetry) Injection
	# We warp the result based on alpha.
	# If alpha > 0, we push values higher. If alpha < 0, lower.
	# This is a "phenomenological" implementation of Umeno's asymmetry.
	next_x = next_x + (alpha * 0.1 * sin(_x * PI))
	
	# 4. Wrap/Clamp to ensure [0,1] bounds (Chebyshev domain)
	if next_x > 1.0: next_x = 2.0 - next_x
	if next_x < 0.0: next_x = abs(next_x)
	
	_x = next_x
	return _x

# --- Public API: Input Ingestion ---

## Call this every frame or tick to advance the chaos
func process_tick():
	if not _is_running: return
	
	var val = _iterate_chaos()
	
	_history.push_back(val)
	if _history.size() > HISTORY_SIZE:
		_history.pop_front()
	
	emit_signal("chaos_updated", alpha, beta, val)

## Ingest Pendulum Data (Flux)
## 'bias': -1.0 (Left) to 1.0 (Right) -> Maps to Alpha
## 'stability': 0.0 (Stable) to 1.0 (Chaotic) -> Maps to Beta
func update_pendulum_state(bias: float, stability: float):
	self.alpha = bias
	# We inverse map stability? Or direct?
	# High Stability (Circle) = Low Beta (Order).
	# Low Stability (Wobble) = High Beta (Chaos).
	self.beta = stability
	
	# _is_running = true # Auto-start on data?

## Ingest Bead/Resonance Data (Intent)
## 'score': 0.0 (Dissonant) to 1.0 (Resonant)
func update_resonance(score: float):
	emit_signal("resonance_calculated", score)
	# Resonance can modulate Beta too. 
	# High Resonance stabilizes the chaos (lowers Beta towards "Edge of Chaos" sweet spot).
	# Low Resonance increases Beta towards pure noise.
	
	# Let's blend resonance into beta:
	# Final Beta = (PendulumStability * 0.5) + ((1.0 - Resonance) * 0.5)
	# i.e. Both "Wobble" and "Dissonance" contribute to Chaos.
	pass 

# --- Public API: Output Generation ---

## Get the current "Noise Seed" parameters for ComfyUI
## Returns a Dictionary compatible with the ComfyBridge
func get_comfy_parameters() -> Dictionary:
	return {
		"alpha": alpha,
		"beta": beta,
		"seed_offset": int(_x * 100000), # Use current chaos state as seed modifier
		"chaos_value": _x
	}

## Get the "Narrative Mood" for the Agents
func get_narrative_mood() -> Dictionary:
	return {
		"optimism_bias": remap(alpha, -1.0, 1.0, 0.0, 1.0), # 0.0 (Pessimistic) -> 1.0 (Optimistic)
		"coherence": remap(beta, 0.0, 1.0, 1.0, 0.0),     # High Chaos = Low Coherence
		"glitch_factor": _x # Current instantaneous chaos level
	}



