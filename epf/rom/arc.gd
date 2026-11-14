class_name EpfArc
extends RefCounted
## fs.arc / chunks.arc: u32 count, then count x (u32 id, u32 offset, u32 size). Entries may be LZ10-compressed.
## id = CRC32(path) where path is "/"+lowercase relative path (fs.arc) or "/chunks/<name>.luc" lowercase (chunks.arc).

var data: PackedByteArray
var entries: Array = []        # [{id, off, size}]
var by_id: Dictionary = {}

static var _crc_table: PackedInt64Array = PackedInt64Array()

static func crc32(s: String) -> int:
	if _crc_table.is_empty():
		_crc_table.resize(256)
		for i in 256:
			var c := i
			for _k in 8: c = (c >> 1) ^ 0xEDB88320 if (c & 1) else (c >> 1)
			_crc_table[i] = c
	var crc := 0xFFFFFFFF
	for b in s.to_utf8_buffer(): crc = _crc_table[(crc ^ b) & 0xFF] ^ (crc >> 8)
	return crc ^ 0xFFFFFFFF

static func parse(bytes: PackedByteArray) -> EpfArc:
	var a := EpfArc.new(); a.data = bytes
	var n := bytes.decode_u32(0)
	for i in n:
		var o := 4 + 12 * i
		var e := {"id": bytes.decode_u32(o), "off": bytes.decode_u32(o + 4), "size": bytes.decode_u32(o + 8)}
		a.entries.append(e); a.by_id[e["id"]] = e
	return a

## Raw entry bytes, LZ10-decompressed when the stream is valid LZ10.
func get_entry(e: Dictionary) -> PackedByteArray:
	var blob := data.slice(e["off"], e["off"] + e["size"])
	var dec = EpfCompress.lz10(blob)
	return dec if dec != null else blob

func get_by_path(path: String) -> PackedByteArray:
	var id := crc32("/" + path.to_lower().lstrip("/"))
	if not by_id.has(id): return PackedByteArray()
	return get_entry(by_id[id])

func get_chunk(name: String) -> PackedByteArray:
	var id := crc32("/chunks/" + name.to_lower() + ".luc")
	if not by_id.has(id): return PackedByteArray()
	return get_entry(by_id[id])
