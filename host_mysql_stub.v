module vjsx

$if !vjsx_mysql ? {
	pub fn (ctx &Context) install_mysql_module() {
		mut mysql_mod := ctx.js_module('mysql')
		connect_fn := ctx.js_function(fn [ctx] (args []Value) Value {
			promise := ctx.js_promise()
			if args.len == 0 || !args[0].is_object() {
				return promise.reject(ctx.js_error(
					message: 'options object is required'
					name:    'TypeError'
				))
			}
			host_value := args[0].get('host')
			defer {
				host_value.free()
			}
			port_value := args[0].get('port')
			defer {
				port_value.free()
			}
			username_value := args[0].get('username')
			defer {
				username_value.free()
			}
			user_value := args[0].get('user')
			defer {
				user_value.free()
			}
			password_value := args[0].get('password')
			defer {
				password_value.free()
			}
			dbname_value := args[0].get('dbname')
			defer {
				dbname_value.free()
			}
			database_value := args[0].get('database')
			defer {
				database_value.free()
			}
			if !host_value.is_undefined() && !host_value.is_null() && !host_value.is_string() {
				return promise.reject(ctx.js_error(
					message: 'options.host must be a string'
					name:    'TypeError'
				))
			}
			if !port_value.is_undefined() && !port_value.is_null() && !port_value.is_number() {
				return promise.reject(ctx.js_error(
					message: 'options.port must be a number'
					name:    'TypeError'
				))
			}
			if !username_value.is_undefined() && !username_value.is_null() && !username_value.is_string() {
				return promise.reject(ctx.js_error(
					message: 'options.username must be a string'
					name:    'TypeError'
				))
			}
			if !user_value.is_undefined() && !user_value.is_null() && !user_value.is_string() {
				return promise.reject(ctx.js_error(
					message: 'options.user must be a string'
					name:    'TypeError'
				))
			}
			if !password_value.is_undefined() && !password_value.is_null() && !password_value.is_string() {
				return promise.reject(ctx.js_error(
					message: 'options.password must be a string'
					name:    'TypeError'
				))
			}
			if !dbname_value.is_undefined() && !dbname_value.is_null() && !dbname_value.is_string() {
				return promise.reject(ctx.js_error(
					message: 'options.dbname must be a string'
					name:    'TypeError'
				))
			}
			if !database_value.is_undefined() && !database_value.is_null() && !database_value.is_string() {
				return promise.reject(ctx.js_error(
					message: 'options.database must be a string'
					name:    'TypeError'
				))
			}
			return promise.reject(ctx.js_error(
				message: 'mysql support is not built in; rerun with -d vjsx_mysql'
				name:    'Error'
			))
		})
		mysql_mod.export('connect', connect_fn)
		default_obj := ctx.js_object()
		default_obj.set('connect', connect_fn)
		mysql_mod.export_default(default_obj)
		mysql_mod.create()
		default_obj.free()
		connect_fn.free()
	}
}
