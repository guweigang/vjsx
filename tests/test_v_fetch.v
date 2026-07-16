import net.http

fn main() {
	resp := http.get('https://qt.gtimg.cn/?q=sh600519') or {
		panic(err)
	}
	bytes := resp.body.bytes()
	println('RESPONSE BODY BYTES LEN: ${bytes.len}')
	println('FIRST 64 BYTES:')
	mut hex := []string{}
	for i in 0 .. 64 {
		if i < bytes.len {
			hex << bytes[i].hex()
		}
	}
	println(hex.join(' '))
}
