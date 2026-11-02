class_name StoryStageOsc
extends RefCounted

## Minimal OSC 1.0 message encoder. Fire-and-forget over UDP.


static func message(address: String, type_tags: String, args: Array) -> PackedByteArray:
	var packet := PackedByteArray()
	packet.append_array(_string(address))
	packet.append_array(_string("," + type_tags))
	var index := 0
	for tag in type_tags:
		var value: Variant = args[index]
		index += 1
		match tag:
			"i":
				packet.append_array(_int(int(value)))
			"f":
				packet.append_array(_float(float(value)))
			"s":
				packet.append_array(_string(str(value)))
	return packet


static func _string(text: String) -> PackedByteArray:
	var raw := text.to_utf8_buffer()
	raw.append(0)
	while raw.size() % 4 != 0:
		raw.append(0)
	return raw


static func _int(value: int) -> PackedByteArray:
	var raw := PackedByteArray()
	raw.resize(4)
	raw.encode_s32(0, value)
	return PackedByteArray([raw[3], raw[2], raw[1], raw[0]])


static func _float(value: float) -> PackedByteArray:
	var raw := PackedByteArray()
	raw.resize(4)
	raw.encode_float(0, value)
	return PackedByteArray([raw[3], raw[2], raw[1], raw[0]])
