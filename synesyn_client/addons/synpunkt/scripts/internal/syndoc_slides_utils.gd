extends RefCounted
class_name SynpunktSyndocSlidesUtils

static func flowdoc_to_slides_deck(flowdoc: Dictionary) -> Dictionary:
	var title := str(flowdoc.get("title", "Slides")).strip_edges()
	var slides: Array = []
	var frames_any: Variant = flowdoc.get("frames", [])
	if typeof(frames_any) == TYPE_ARRAY:
		var frames: Array = frames_any
		var idx := 1
		for f_any in frames:
			if typeof(f_any) != TYPE_DICTIONARY:
				continue
			var f: Dictionary = f_any
			var blocks_any: Variant = f.get("blocks", [])
			var blocks: Array = blocks_any if typeof(blocks_any) == TYPE_ARRAY else []
			var slide_title := ""
			var paragraphs: Array = []
			var bullets: Array = []
			var highlights: Array = []
			var subtitle := ""
			var section := ""
			for b_any in blocks:
				if typeof(b_any) != TYPE_DICTIONARY:
					continue
				var b: Dictionary = b_any
				var t := str(b.get("type", "p")).strip_edges().to_lower()
				var txt := str(b.get("text", "")).strip_edges()
				if txt.is_empty():
					continue
				if (t in ["h1", "h2", "h3"]) and slide_title.is_empty():
					slide_title = txt
				elif t == "p":
					paragraphs.append(txt)
				elif t == "li":
					bullets.append(txt)
				elif t == "highlight":
					highlights.append(txt)
			if slide_title.is_empty():
				slide_title = str(f.get("id", "Slide %d" % idx)).strip_edges()
			slides.append(
				{
					"id": idx,
					"title": slide_title,
					"section": section,
					"subtitle": subtitle,
					"paragraphs": paragraphs,
					"bullets": bullets,
					"highlights": highlights,
					"images": [],
					"links": [],
				}
			)
			idx += 1
	return {
		"meta": {
			"title": title,
			"exported_at": Time.get_datetime_string_from_system(false, true),
			"source": "synpunkt",
		},
		"slides": slides,
	}


static func slides_deck_to_flowdoc(deck: Dictionary) -> Dictionary:
	var meta_any: Variant = deck.get("meta", {})
	var meta: Dictionary = meta_any if typeof(meta_any) == TYPE_DICTIONARY else {}
	var title := str(meta.get("title", "Imported slides")).strip_edges()
	if title.is_empty():
		title = "Imported slides"
	var frames: Array = []
	var slides_any: Variant = deck.get("slides", [])
	if typeof(slides_any) == TYPE_ARRAY:
		for s_any in (slides_any as Array):
			if typeof(s_any) != TYPE_DICTIONARY:
				continue
			var s: Dictionary = s_any
			var sid := str(s.get("id", "")).strip_edges()
			if sid.is_empty():
				sid = "slide_%d" % (frames.size() + 1)
			var blocks: Array = []
			var st := str(s.get("title", "")).strip_edges()
			if not st.is_empty():
				blocks.append({"type": "h1", "text": st})
			var subtitle := str(s.get("subtitle", "")).strip_edges()
			if not subtitle.is_empty():
				blocks.append({"type": "h2", "text": subtitle})
			var paragraphs_any: Variant = s.get("paragraphs", [])
			if typeof(paragraphs_any) == TYPE_ARRAY:
				for p in (paragraphs_any as Array):
					var txt := str(p).strip_edges()
					if not txt.is_empty():
						blocks.append({"type": "p", "text": txt})
			var bullets_any: Variant = s.get("bullets", [])
			if typeof(bullets_any) == TYPE_ARRAY:
				for b in (bullets_any as Array):
					var txt := str(b).strip_edges()
					if not txt.is_empty():
						blocks.append({"type": "li", "text": txt})
			var highlights_any: Variant = s.get("highlights", [])
			if typeof(highlights_any) == TYPE_ARRAY:
				for h in (highlights_any as Array):
					var txt := str(h).strip_edges()
					if not txt.is_empty():
						blocks.append({"type": "highlight", "text": txt})
			frames.append({"id": sid, "kind": "document", "transform": {"x": 0, "y": 0, "w": 960, "h": 540}, "blocks": blocks})
	return {
		"schema": "ui.syndoc",
		"schema_version": "0.2.0",
		"title": title,
		"created_at": Time.get_datetime_string_from_system(false, true),
		"refs": {},
		"frames": frames,
	}
