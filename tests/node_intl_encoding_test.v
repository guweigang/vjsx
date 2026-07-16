import vjsx

fn test_node_runtime_text_decoder_gbk_and_intl_datetime_format() {
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		process_args: ['inline.js']
	})
	defer {
		session.close()
	}
	ctx := session.context()
	value := ctx.eval('[
		new TextDecoder("gbk").decode(new Uint8Array([0x56, 0xb4, 0xf3, 0xb7, 0xa8, 0xba, 0xc3])),
		new Intl.DateTimeFormat("en-US", {
			year: "numeric",
			month: "2-digit",
			day: "2-digit",
			hour: "2-digit",
			minute: "2-digit",
			second: "2-digit",
			hour12: false,
			timeZone: "UTC",
		}).format(new Date(Date.UTC(2024, 6, 15, 14, 30, 45))),
	].join("\\n")') or {
		panic(err)
	}
	defer {
		value.free()
	}
	assert value.to_string() == 'V大法好\n07/15/2024, 14:30:45'
}
