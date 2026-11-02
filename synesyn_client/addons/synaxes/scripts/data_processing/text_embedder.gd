extends RefCounted
## Pure GDScript text embedder using TF-IDF with feature hashing.
##
## Tier 2 (self-contained): produces content-aware vectors without any external
## dependencies. Texts sharing similar vocabulary will cluster together.
## Not as semantically rich as neural embeddings (Tier 3) but dramatically
## better than random vectors and works offline with zero setup.

const DEFAULT_DIM := 64

## Embed a batch of texts into fixed-dimension vectors.
## Returns Array of Array[float], one vector per input text.
func embed_batch(texts: Array, dim: int = DEFAULT_DIM) -> Array:
	if texts.is_empty():
		return []

	# 1) Tokenize all texts
	var all_tokens: Array = []
	for text_any in texts:
		all_tokens.append(_tokenize(str(text_any)))

	# 2) Document frequency per hash bucket (for IDF)
	var doc_freq: Dictionary = {}
	var n_docs := all_tokens.size()
	for tokens in all_tokens:
		var seen: Dictionary = {}
		for tok in tokens:
			var h := _hash_token(tok, dim)
			if not seen.has(h):
				seen[h] = true
				doc_freq[h] = doc_freq.get(h, 0) + 1

	# 3) Compute TF-IDF vector per document
	var vectors: Array = []
	for tokens in all_tokens:
		# Term frequency in this document
		var tf: Dictionary = {}
		for tok in tokens:
			var h := _hash_token(tok, dim)
			tf[h] = tf.get(h, 0) + 1

		# Build vector
		var vec: Array = []
		vec.resize(dim)
		for i in range(dim):
			vec[i] = 0.0

		for h in tf:
			var tf_val := float(tf[h])
			var df := float(doc_freq.get(h, 1))
			# Smoothed IDF: log((N+1) / (df+1)) + 1
			var idf := log(float(n_docs + 1) / (df + 1.0)) + 1.0
			vec[h] += tf_val * idf

		vectors.append(_l2_normalize(vec))
	return vectors

## Embed a single text. Convenience wrapper.
func embed_single(text: String, dim: int = DEFAULT_DIM) -> Array:
	var result := embed_batch([text], dim)
	if result.is_empty():
		return []
	return result[0]

# ── Internals ─────────────────────────────────────────────────────────────

func _tokenize(text: String) -> Array:
	var lower := text.to_lower()
	var tokens: Array = []
	var current := ""
	for ch_idx in range(lower.length()):
		var ch := lower[ch_idx]
		if _is_alnum(ch):
			current += ch
		else:
			if current.length() >= 2:
				tokens.append(current)
			current = ""
	if current.length() >= 2:
		tokens.append(current)

	# Add bigrams for slightly richer semantics
	var bigrams: Array = []
	for i in range(tokens.size() - 1):
		bigrams.append(tokens[i] + "_" + tokens[i + 1])
	tokens.append_array(bigrams)
	return tokens

func _is_alnum(ch: String) -> bool:
	var code := ch.unicode_at(0)
	return (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)

func _hash_token(token: String, dim: int) -> int:
	var h := token.hash()
	return absi(h) % dim

func _l2_normalize(vec: Array) -> Array:
	var sq_sum := 0.0
	for val in vec:
		sq_sum += val * val
	if sq_sum < 1e-12:
		return vec
	var norm_val := sqrt(sq_sum)
	var result: Array = []
	for val in vec:
		result.append(val / norm_val)
	return result
