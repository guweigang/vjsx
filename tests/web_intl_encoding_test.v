import vjsx
import web

fn test_browser_runtime_text_decoder_gbk_and_intl_datetime_format() {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	web.inject_browser_runtime(ctx)
	value := ctx.eval('[
		new TextDecoder("gbk").decode(new Uint8Array([0x56, 0xb4, 0xf3, 0xb7, 0xa8, 0xba, 0xc3])),
		(() => {
			const decoder = new TextDecoder("gbk");
			return decoder.decode(new Uint8Array([0xb4]), { stream: true }) +
				decoder.decode(new Uint8Array([0xf3]));
		})(),
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
		new Intl.DateTimeFormat("zh-CN", {
			weekday: "long",
			year: "numeric",
			month: "2-digit",
			day: "2-digit",
			timeZone: "UTC",
		}).formatToParts(new Date(Date.UTC(2024, 6, 15))).map((part) => part.type + ":" + part.value).join("|"),
	].join("\\n")') or {
		panic(err)
	}
	defer {
		value.free()
	}
	assert value.to_string() == 'V大法好\n大\n07/15/2024, 14:30:45\nyear:2024|literal:/|month:07|literal:/|day:15|literal: |weekday:星期一'
}
