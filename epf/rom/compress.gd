class_name EpfCompress
extends RefCounted
## LZ10 (Nintendo, forward) and BLZ ("code compression", backward LZ used for ARM9/overlays).

static func lz10(data: PackedByteArray):
	## Returns decompressed bytes, or null if data is not a valid LZ10 stream.
	if data.size() < 8 or data[0] != 0x10: return null
	var want := data[1] | (data[2] << 8) | (data[3] << 16)
	if want == 0 or want > 64 * 1024 * 1024: return null
	var out := PackedByteArray(); out.resize(want)
	var si := 4; var di := 0; var n := data.size()
	while di < want:
		if si >= n: return null
		var flags := data[si]; si += 1
		for bit in 8:
			if di >= want: break
			if (flags & (0x80 >> bit)) == 0:
				if si >= n: return null
				out[di] = data[si]; di += 1; si += 1
			else:
				if si + 1 >= n: return null
				var b1 := data[si]; var b2 := data[si + 1]; si += 2
				var length := (b1 >> 4) + 3
				var disp := (((b1 & 0x0F) << 8) | b2) + 1
				if disp > di: return null
				for _i in length:
					if di >= want: break
					out[di] = out[di - disp]; di += 1
	return out

static func blz(data: PackedByteArray) -> PackedByteArray:
	## Backward LZ (overlays). Returns data unchanged when not compressed.
	var n := data.size()
	if n < 8: return data
	var extra := data.decode_u32(n - 4)
	if extra == 0: return data
	var w := data.decode_u32(n - 8)
	var header_len := w >> 24
	var comp_len := w & 0xFFFFFF
	if comp_len > n: comp_len = n
	var passthrough := n - comp_len
	var out_len := n + extra - passthrough
	var dec := PackedByteArray(); dec.resize(out_len)
	var comp_end := passthrough + comp_len - header_len   # exclusive end of compressed payload
	var out_size := 0; var read := 0; var flags := 0; var mask := 1
	while out_size < out_len:
		if mask == 1:
			flags = data[comp_end - 1 - read]; read += 1; mask = 0x80
		else:
			mask >>= 1
		if (flags & mask) != 0:
			var b1 := data[comp_end - 1 - read]; read += 1
			var b2 := data[comp_end - 1 - read]; read += 1
			var length := (b1 >> 4) + 3
			var disp := (((b1 & 0x0F) << 8) | b2) + 3
			if disp > out_size: disp = 2
			var bi := out_size - disp
			for _i in length:
				if out_size >= out_len: break
				dec[out_len - 1 - out_size] = dec[out_len - 1 - bi]
				bi += 1; out_size += 1
		else:
			dec[out_len - 1 - out_size] = data[comp_end - 1 - read]
			read += 1; out_size += 1
	var res := data.slice(0, passthrough)
	res.append_array(dec)
	return res
