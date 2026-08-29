module vjsx

import crypto.rand
import encoding.hex

fn secure_random_hex(byte_count int) !string {
	return hex.encode(rand.bytes(byte_count)!)
}

fn secure_random_uuid_v4() !string {
	mut bytes := rand.bytes(16)!
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	encoded := hex.encode(bytes)
	return '${encoded[..8]}-${encoded[8..12]}-${encoded[12..16]}-${encoded[16..20]}-${encoded[20..]}'
}
