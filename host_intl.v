module vjsx

import time

@[manualfree]
pub fn host_intl_date_time_parts(this Value, args []Value) Value {
	if args.len == 0 {
		err := this.ctx.js_type_error(message: 'date milliseconds are required')
		return this.ctx.js_throw(err)
	}
	ms := args[0].to_i64()
	time_zone := if args.len > 1 { args[1].str() } else { '' }
	mut t := time.unix_milli(ms)
	if time_zone != 'UTC' {
		t = t.local()
	}
	obj := this.ctx.js_object()
	obj.set('year', t.year)
	obj.set('month', t.month)
	obj.set('day', t.day)
	obj.set('hour', t.hour)
	obj.set('minute', t.minute)
	obj.set('second', t.second)
	obj.set('weekday', t.day_of_week() % 7)
	return obj
}
