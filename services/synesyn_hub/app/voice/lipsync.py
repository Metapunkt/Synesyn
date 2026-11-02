from __future__ import annotations

from typing import Dict, List


def generate_simple_lipsync(text: str, duration: float) -> List[Dict]:
	"""
	Placeholder lipsync generator (mirrors the existing reference service approach).
	Produces time-keyed mouth shape hints, suitable for later replacement.
	"""
	words = text.split()
	if not words or duration <= 0:
		return []
	keyframes: List[Dict] = []
	time_per_word = duration / max(1, len(words))
	current_time = 0.0
	for word in words:
		vowels = sum(1 for c in word.lower() if c in "aeiou")
		consonants = max(0, len(word) - vowels)
		word_frames = max(2, vowels + consonants // 2)
		frame_duration = time_per_word / word_frames
		for i in range(word_frames):
			if i < vowels:
				mouth_shape = "mouth_a" if "a" in word.lower() else "mouth_e"
				mouth_open = 0.7
			else:
				mouth_shape = "mouth_m" if any(c in word.lower() for c in "bmp") else "mouth_s"
				mouth_open = 0.3
			keyframes.append({"time": current_time, "mouth_open": mouth_open, "mouth_shape": mouth_shape})
			current_time += frame_duration
	return keyframes


