module runtimejs

import time
import vjsx

fn cli_browser_intl_boot(ctx &vjsx.Context, boot vjsx.Value) {
	boot.set('intl_date_time_parts', ctx.js_function_this(fn [ctx] (this vjsx.Value, args []vjsx.Value) vjsx.Value {
		if args.len == 0 {
			err := ctx.js_type_error(message: 'date milliseconds are required')
			return ctx.js_throw(err)
		}
		ms := args[0].to_i64()
		time_zone := if args.len > 1 { args[1].str() } else { '' }
		mut t := time.unix_milli(ms)
		if time_zone != 'UTC' {
			t = t.local()
		}
		obj := ctx.js_object()
		obj.set('year', t.year)
		obj.set('month', t.month)
		obj.set('day', t.day)
		obj.set('hour', t.hour)
		obj.set('minute', t.minute)
		obj.set('second', t.second)
		obj.set('weekday', t.day_of_week() % 7)
		return obj
	}))
}
