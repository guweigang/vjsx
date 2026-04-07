module vjsx

$if vjsx_mysql ? {
	import db.mysql as vmysql

	struct HostMySqlConnectConfig {
		host     string = '127.0.0.1'
		port     u32    = 3306
		username string
		password string
		dbname   string
	}

	@[heap]
	struct HostMySqlConn {
	mut:
		db           vmysql.DB
		closed       bool
		in_tx        bool
		stmts        []&HostMySqlStmt
		cached_stmts map[string]&HostMySqlStmt
	}

	struct HostMySqlPreparedRows {
		field_names []string
		rows        []map[string]string
	}

	struct HostMySqlExecResult {
		rows           []map[string]string
		changes        i64
		rows_affected  i64
		last_insert_id i64
	}

	struct HostMySqlStmt {
	mut:
		conn       &HostMySqlConn = unsafe { nil }
		query_text string
		closed     bool
		obj_ref    Value
		cache_key  string
	}

	struct HostMySqlParam {
		value   string
		is_null bool
	}

	fn mysql_error_value(ctx &Context, message string, name string) Value {
		return ctx.js_error(
			message: message
			name:    name
		)
	}

	fn mysql_error_message(err IError) string {
		line := err.msg().split_into_lines()[0]
		if idx := line.index(': ') {
			prefix := line[..idx]
			if prefix.ends_with('Error') {
				return line[idx + 2..]
			}
		}
		return line
	}

	fn mysql_begin_transaction(mut conn HostMySqlConn) ! {
		conn.db.exec('start transaction')!
	}

	fn mysql_commit_transaction(mut conn HostMySqlConn) ! {
		conn.db.exec('commit')!
	}

	fn mysql_rollback_transaction(mut conn HostMySqlConn) ! {
		conn.db.exec('rollback')!
	}

	fn mysql_rollback_error_value(ctx &Context, mut conn HostMySqlConn, fallback_message string) Value {
		mysql_rollback_transaction(mut conn) or {
			return mysql_error_value(ctx, mysql_error_message(err), 'Error')
		}
		return mysql_error_value(ctx, fallback_message, 'Error')
	}

	fn mysql_set_transaction_state(mut conn HostMySqlConn, conn_obj Value, active bool) {
		conn.in_tx = active
		conn_obj.set('inTransaction', active)
	}

	fn mysql_mark_stmt_closed(mut stmt HostMySqlStmt) {
		if stmt.closed {
			return
		}
		stmt.closed = true
		if stmt.cache_key != '' {
			if cached_stmt := stmt.conn.cached_stmts[stmt.cache_key] {
				if cached_stmt == stmt {
					stmt.conn.cached_stmts.delete(stmt.cache_key)
				}
			}
		}
		stmt.obj_ref.set('closed', true)
	}

	fn mysql_close_conn_statements(mut conn HostMySqlConn) {
		for mut stmt in conn.stmts {
			mysql_mark_stmt_closed(mut stmt)
		}
		conn.cached_stmts = map[string]&HostMySqlStmt{}
	}

	fn mysql_close_host_conn(mut conn HostMySqlConn) {
		if conn.closed {
			return
		}
		if conn.in_tx {
			mysql_rollback_transaction(mut conn) or {}
		}
		mysql_close_conn_statements(mut conn)
		conn.db.close() or {}
		conn.closed = true
		conn.in_tx = false
	}

	fn mysql_rows_value_from_maps(ctx &Context, rows []map[string]string) Value {
		arr := ctx.js_array()
		for i, row in rows {
			obj := mysql_row_value_from_map(ctx, row)
			arr.set(i, obj)
			obj.free()
		}
		return arr
	}

	fn mysql_row_value_from_map(ctx &Context, row map[string]string) Value {
		obj := ctx.js_object()
		for key, val in row {
			obj.set(key, val)
		}
		return obj
	}

	fn mysql_first_row_value_from_maps(ctx &Context, rows []map[string]string) Value {
		if rows.len == 0 {
			return ctx.js_null()
		}
		return mysql_row_value_from_map(ctx, rows[0])
	}

	fn mysql_first_scalar_value_from_result(ctx &Context, rows HostMySqlPreparedRows) Value {
		if rows.rows.len == 0 {
			return ctx.js_null()
		}
		first_row := rows.rows[0].clone()
		if rows.field_names.len > 0 {
			first_name := rows.field_names[0]
			if first_name in first_row {
				return ctx.js_string(first_row[first_name])
			}
		}
		keys := first_row.keys()
		if keys.len == 0 {
			return ctx.js_null()
		}
		return ctx.js_string(first_row[keys[0]])
	}

	fn mysql_error_name_from_message(message string) string {
		return if message in ['params must be an array', 'param batches must be an array',
			'each param batch must be an array'] {
			'TypeError'
		} else {
			'Error'
		}
	}

	fn mysql_stmt_object(ctx &Context, mut stmt HostMySqlStmt) Value {
		obj := ctx.js_object()
		obj.set('driver', 'mysql')
		obj.set('supportsTransactions', true)
		obj.set('sql', stmt.query_text)
		obj.set('kind', sql_stmt_kind(stmt.query_text))
		obj.set('closed', stmt.closed)
		stmt.obj_ref = obj.dup_value()
		to_string_fn := ctx.js_function(fn [ctx, stmt] (args []Value) Value {
			return ctx.js_string('mysql.Statement{kind: ${sql_stmt_kind(stmt.query_text)}, closed: ${stmt.closed}, sql: ${stmt.query_text}}')
		})
		query_fn := ctx.js_function(fn [ctx, mut stmt] (args []Value) Value {
			mut query_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if stmt.closed {
				query_err = mysql_error_value(ctx, 'mysql statement is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			if stmt.conn.closed {
				query_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			rows := mysql_query_maps(mut stmt.conn, stmt.query_text, args, 0) or {
				query_err = mysql_error_value(ctx, err.msg(), mysql_error_name_from_message(err.msg()))
				unsafe {
					goto reject
				}
				HostMySqlPreparedRows{}
			}
			return promise.resolve(mysql_rows_value_from_maps(ctx, rows.rows))
			reject:
			return promise.reject(query_err)
		})
		query_one_fn := ctx.js_function(fn [ctx, mut stmt] (args []Value) Value {
			mut query_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if stmt.closed {
				query_err = mysql_error_value(ctx, 'mysql statement is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			if stmt.conn.closed {
				query_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			rows := mysql_query_maps(mut stmt.conn, stmt.query_text, args, 0) or {
				query_err = mysql_error_value(ctx, err.msg(), mysql_error_name_from_message(err.msg()))
				unsafe {
					goto reject
				}
				HostMySqlPreparedRows{}
			}
			return promise.resolve(mysql_first_row_value_from_maps(ctx, rows.rows))
			reject:
			return promise.reject(query_err)
		})
		scalar_fn := ctx.js_function(fn [ctx, mut stmt] (args []Value) Value {
			mut query_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if stmt.closed {
				query_err = mysql_error_value(ctx, 'mysql statement is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			if stmt.conn.closed {
				query_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			rows := mysql_query_maps(mut stmt.conn, stmt.query_text, args, 0) or {
				query_err = mysql_error_value(ctx, err.msg(), mysql_error_name_from_message(err.msg()))
				unsafe {
					goto reject
				}
				HostMySqlPreparedRows{}
			}
			return promise.resolve(mysql_first_scalar_value_from_result(ctx, rows))
			reject:
			return promise.reject(query_err)
		})
		query_many_fn := ctx.js_function(fn [ctx, mut stmt] (args []Value) Value {
			mut query_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if stmt.closed {
				query_err = mysql_error_value(ctx, 'mysql statement is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			if stmt.conn.closed {
				query_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			batches := mysql_param_batches(args, 0) or {
				query_err = mysql_error_value(ctx, err.msg(), 'TypeError')
				unsafe {
					goto reject
				}
				[][]HostMySqlParam{}
			}
			results := ctx.js_array()
				for i, params in batches {
					rows := mysql_query_maps_with_params(mut stmt.conn.db, stmt.query_text, params) or {
					results.free()
					query_err = mysql_error_value(ctx, err.msg(), 'Error')
					unsafe {
						goto reject
					}
					HostMySqlPreparedRows{}
				}
				rows_value := mysql_rows_value_from_maps(ctx, rows.rows)
				results.set(i, rows_value)
				rows_value.free()
			}
			return promise.resolve(results)
			reject:
			return promise.reject(query_err)
		})
		exec_fn := ctx.js_function(fn [ctx, mut stmt] (args []Value) Value {
			mut exec_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if stmt.closed {
				exec_err = mysql_error_value(ctx, 'mysql statement is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			if stmt.conn.closed {
				exec_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			result := ctx.js_object()
			params := mysql_params(args, 0) or {
				exec_err = mysql_error_value(ctx, err.msg(), mysql_error_name_from_message(err.msg()))
				unsafe {
					goto reject
				}
				[]HostMySqlParam{}
			}
			mut exec_rows := HostMySqlPreparedRows{}
			mut changes := i64(0)
			mut rows_affected := i64(0)
			mut last_insert_id := i64(0)
			if params.len > 0 {
				exec_meta := mysql_exec_result_with_params(mut stmt.conn.db, stmt.query_text, params) or {
					exec_err = mysql_error_value(ctx, err.msg(), mysql_error_name_from_message(err.msg()))
					unsafe {
						goto reject
					}
					HostMySqlExecResult{}
				}
				exec_rows = HostMySqlPreparedRows{
					rows: exec_meta.rows
				}
				changes = exec_meta.changes
				rows_affected = exec_meta.rows_affected
				last_insert_id = exec_meta.last_insert_id
			} else {
				exec_rows = mysql_exec_maps(mut stmt.conn, stmt.query_text, args, 0) or {
					exec_err = mysql_error_value(ctx, err.msg(), mysql_error_name_from_message(err.msg()))
					unsafe {
						goto reject
					}
					HostMySqlPreparedRows{}
				}
				changes = i64(stmt.conn.db.affected_rows())
				rows_affected = i64(stmt.conn.db.affected_rows())
				last_insert_id = stmt.conn.db.last_id()
			}
			rows_value := mysql_rows_value_from_maps(ctx, exec_rows.rows)
			result.set('rows', rows_value)
			result.set('changes', changes)
			result.set('rowsAffected', rows_affected)
			result.set('lastInsertRowid', last_insert_id)
			result.set('insertId', last_insert_id)
			rows_value.free()
			return promise.resolve(result)
			reject:
			return promise.reject(exec_err)
		})
		exec_many_fn := ctx.js_function(fn [ctx, mut stmt] (args []Value) Value {
			mut exec_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if stmt.closed {
				exec_err = mysql_error_value(ctx, 'mysql statement is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			if stmt.conn.closed {
				exec_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			batches := mysql_param_batches(args, 0) or {
				exec_err = mysql_error_value(ctx, err.msg(), 'TypeError')
				unsafe {
					goto reject
				}
				[][]HostMySqlParam{}
			}
			results := ctx.js_array()
			for i, params in batches {
				exec_meta := mysql_exec_result_with_params(mut stmt.conn.db, stmt.query_text, params) or {
					results.free()
					exec_err = mysql_error_value(ctx, err.msg(), 'Error')
					unsafe {
						goto reject
					}
					HostMySqlExecResult{}
				}
				result := ctx.js_object()
				rows_value := mysql_rows_value_from_maps(ctx, exec_meta.rows)
				result.set('rows', rows_value)
				result.set('changes', exec_meta.changes)
				result.set('rowsAffected', exec_meta.rows_affected)
				result.set('lastInsertRowid', exec_meta.last_insert_id)
				result.set('insertId', exec_meta.last_insert_id)
				rows_value.free()
				results.set(i, result)
				result.free()
			}
			return promise.resolve(results)
			reject:
			return promise.reject(exec_err)
		})
		close_fn := ctx.js_function(fn [ctx, mut stmt] (args []Value) Value {
			promise := ctx.js_promise()
			mysql_mark_stmt_closed(mut stmt)
			return promise.resolve(ctx.js_undefined())
		})
		obj.set('query', query_fn)
		obj.set('queryOne', query_one_fn)
		obj.set('scalar', scalar_fn)
		obj.set('queryMany', query_many_fn)
		obj.set('exec', exec_fn)
		obj.set('execMany', exec_many_fn)
		obj.set('close', close_fn)
		obj.set('toString', to_string_fn)
		to_string_fn.free()
		query_fn.free()
		query_one_fn.free()
		scalar_fn.free()
		query_many_fn.free()
		exec_fn.free()
		exec_many_fn.free()
		close_fn.free()
		return obj
	}

	fn mysql_params_len(args []Value, index int) !int {
		if index >= args.len || args[index].is_undefined() || args[index].is_null() {
			return 0
		}
		if !args[index].is_array() {
			return error('params must be an array')
		}
		length_value := args[index].get('length')
		defer {
			length_value.free()
		}
		return length_value.to_int()
	}

	fn mysql_params(args []Value, index int) ![]HostMySqlParam {
		param_len := mysql_params_len(args, index)!
		mut params := []HostMySqlParam{cap: param_len}
		for i in 0 .. param_len {
			value := args[index].get(i)
			if value.is_null() || value.is_undefined() {
				params << HostMySqlParam{
					is_null: true
				}
			} else {
				params << HostMySqlParam{
					value: if value.is_bool() {
						if value.to_bool() { '1' } else { '0' }
					} else {
						value.to_string()
					}
				}
			}
			value.free()
		}
		return params
	}

	fn mysql_param_batches(args []Value, index int) ![][]HostMySqlParam {
		if index >= args.len || args[index].is_undefined() || args[index].is_null() {
			return [][]HostMySqlParam{}
		}
		if !args[index].is_array() {
			return error('param batches must be an array')
		}
		length_value := args[index].get('length')
		defer {
			length_value.free()
		}
		batch_len := length_value.to_int()
		mut batches := [][]HostMySqlParam{cap: batch_len}
		for i in 0 .. batch_len {
			batch_value := args[index].get(i)
			if !batch_value.is_array() {
				batch_value.free()
				return error('each param batch must be an array')
			}
			params_len_value := batch_value.get('length')
			params_len := params_len_value.to_int()
			params_len_value.free()
			mut params := []HostMySqlParam{cap: params_len}
			for j in 0 .. params_len {
				param_value := batch_value.get(j)
				if param_value.is_null() || param_value.is_undefined() {
					params << HostMySqlParam{
						is_null: true
					}
				} else {
					params << HostMySqlParam{
						value: if param_value.is_bool() {
							if param_value.to_bool() { '1' } else { '0' }
						} else {
							param_value.to_string()
						}
					}
				}
				param_value.free()
			}
			batch_value.free()
			batches << params
		}
		return batches
	}

	fn mysql_stmt_query_columns(mut db vmysql.DB, query string) ![]string {
		mut stmt := db.init_stmt(query)
		defer {
			stmt.close() or {}
		}
		stmt.prepare()!
		metadata := stmt.gen_metadata()
		if metadata == unsafe { nil } {
			return []string{}
		}
		field_count := vmysql.Result{
			result: metadata
		}.n_fields()
		field_defs := stmt.fetch_fields(metadata)
		mut columns := []string{cap: field_count}
		for i in 0 .. field_count {
			columns << unsafe { cstring_to_vstring(field_defs[i].name) }
		}
		C.mysql_free_result(metadata)
		return columns
	}

	fn mysql_query_maps_with_params(mut db vmysql.DB, query_text string, params []HostMySqlParam) !HostMySqlPreparedRows {
		columns := mysql_stmt_query_columns(mut db, query_text) or { []string{} }
		stmt := db.prepare(query_text)!
		defer {
			stmt.close()
		}
		response := stmt.execute(params.map(if it.is_null { '' } else { it.value }))!
		mut rows := []map[string]string{}
		for response_row in response {
			mut item := map[string]string{}
			for i, value in response_row.vals {
				key := if i < columns.len && columns[i] != '' { columns[i] } else { '${i}' }
				item[key] = value
			}
			rows << item
		}
		return HostMySqlPreparedRows{
			field_names: columns
			rows:        rows
		}
	}

	fn mysql_query_maps(mut conn HostMySqlConn, query_text string, args []Value, index int) !HostMySqlPreparedRows {
		params := mysql_params(args, index)!
		return if params.len > 0 {
			mysql_query_maps_with_params(mut conn.db, query_text, params)!
		} else {
			mut result := conn.db.query(query_text)!
			defer {
				unsafe { result.free() }
			}
			HostMySqlPreparedRows{
				rows: result.maps()
			}
		}
	}

	fn mysql_exec_result_with_params(mut db vmysql.DB, query_text string, params []HostMySqlParam) !HostMySqlExecResult {
		mut stmt := db.init_stmt(query_text)
		defer {
			stmt.close() or {}
		}
		stmt.prepare()!
		for param in params {
			if param.is_null {
				stmt.bind_null()
			} else {
				stmt.bind_text(param.value)
			}
		}
		if params.len > 0 {
			stmt.bind_params()!
		}
		stmt.execute()!
		affected := i64(db.affected_rows())
		last_id := db.last_id()
		return HostMySqlExecResult{
			rows:           []map[string]string{}
			changes:        affected
			rows_affected:  affected
			last_insert_id: last_id
		}
	}

	fn mysql_exec_maps(mut conn HostMySqlConn, query_text string, args []Value, index int) !HostMySqlPreparedRows {
		params := mysql_params(args, index)!
		return if params.len > 0 {
			exec_meta := mysql_exec_result_with_params(mut conn.db, query_text, params)!
			HostMySqlPreparedRows{
				rows: exec_meta.rows
			}
		} else {
			response := conn.db.exec(query_text)!
			mut maps := []map[string]string{}
			for row in response {
				mut item := map[string]string{}
				for i, val in row.vals {
					item['${i}'] = val
				}
				maps << item
			}
			HostMySqlPreparedRows{
				rows: maps
			}
		}
	}

	fn mysql_connect_config(arg Value) !HostMySqlConnectConfig {
		if !arg.is_object() {
			return error('options object is required')
		}
		host_value := arg.get('host')
		defer {
			host_value.free()
		}
		port_value := arg.get('port')
		defer {
			port_value.free()
		}
		username_value := arg.get('username')
		defer {
			username_value.free()
		}
		user_value := arg.get('user')
		defer {
			user_value.free()
		}
		password_value := arg.get('password')
		defer {
			password_value.free()
		}
		dbname_value := arg.get('dbname')
		defer {
			dbname_value.free()
		}
		database_value := arg.get('database')
		defer {
			database_value.free()
		}
		if !host_value.is_undefined() && !host_value.is_null() && !host_value.is_string() {
			return error('options.host must be a string')
		}
		if !port_value.is_undefined() && !port_value.is_null() && !port_value.is_number() {
			return error('options.port must be a number')
		}
		if !username_value.is_undefined() && !username_value.is_null() && !username_value.is_string() {
			return error('options.username must be a string')
		}
		if !user_value.is_undefined() && !user_value.is_null() && !user_value.is_string() {
			return error('options.user must be a string')
		}
		if !password_value.is_undefined() && !password_value.is_null() && !password_value.is_string() {
			return error('options.password must be a string')
		}
		if !dbname_value.is_undefined() && !dbname_value.is_null() && !dbname_value.is_string() {
			return error('options.dbname must be a string')
		}
		if !database_value.is_undefined() && !database_value.is_null() && !database_value.is_string() {
			return error('options.database must be a string')
		}
		username := if username_value.is_string() {
			username_value.to_string()
		} else if user_value.is_string() {
			user_value.to_string()
		} else {
			''
		}
		dbname := if dbname_value.is_string() {
			dbname_value.to_string()
		} else if database_value.is_string() {
			database_value.to_string()
		} else {
			''
		}
		return HostMySqlConnectConfig{
			host:     if host_value.is_string() { host_value.to_string() } else { '127.0.0.1' }
			port:     if port_value.is_number() { u32(port_value.to_int()) } else { u32(3306) }
			username: username
			password: if password_value.is_string() { password_value.to_string() } else { '' }
			dbname:   dbname
		}
	}

	fn mysql_conn_object(ctx &Context, mut conn HostMySqlConn) Value {
		obj := ctx.js_object()
		obj.set('driver', 'mysql')
		obj.set('supportsTransactions', true)
		obj.set('inTransaction', conn.in_tx)
		to_string_fn := ctx.js_function(fn [ctx, conn] (args []Value) Value {
			return ctx.js_string('mysql.Connection{closed: ${conn.closed}, inTransaction: ${conn.in_tx}}')
		})
		query_fn := ctx.js_function(fn [ctx, mut conn] (args []Value) Value {
			mut query_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if conn.closed {
				query_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			if args.len == 0 {
				query_err = mysql_error_value(ctx, 'sql is required', 'TypeError')
				unsafe {
					goto reject
				}
			}
			query_text := args[0].to_string()
			rows := mysql_query_maps(mut conn, query_text, args, 1) or {
				query_err = mysql_error_value(ctx, err.msg(), mysql_error_name_from_message(err.msg()))
				unsafe {
					goto reject
				}
				HostMySqlPreparedRows{}
			}
			return promise.resolve(mysql_rows_value_from_maps(ctx, rows.rows))
			reject:
			return promise.reject(query_err)
		})
		query_one_fn := ctx.js_function(fn [ctx, mut conn] (args []Value) Value {
			mut query_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if conn.closed {
				query_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			if args.len == 0 {
				query_err = mysql_error_value(ctx, 'sql is required', 'TypeError')
				unsafe {
					goto reject
				}
			}
			query_text := args[0].to_string()
			rows := mysql_query_maps(mut conn, query_text, args, 1) or {
				query_err = mysql_error_value(ctx, err.msg(), mysql_error_name_from_message(err.msg()))
				unsafe {
					goto reject
				}
				HostMySqlPreparedRows{}
			}
			return promise.resolve(mysql_first_row_value_from_maps(ctx, rows.rows))
			reject:
			return promise.reject(query_err)
		})
		scalar_fn := ctx.js_function(fn [ctx, mut conn] (args []Value) Value {
			mut query_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if conn.closed {
				query_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			if args.len == 0 {
				query_err = mysql_error_value(ctx, 'sql is required', 'TypeError')
				unsafe {
					goto reject
				}
			}
			query_text := args[0].to_string()
			rows := mysql_query_maps(mut conn, query_text, args, 1) or {
				query_err = mysql_error_value(ctx, err.msg(), mysql_error_name_from_message(err.msg()))
				unsafe {
					goto reject
				}
				HostMySqlPreparedRows{}
			}
			return promise.resolve(mysql_first_scalar_value_from_result(ctx, rows))
			reject:
			return promise.reject(query_err)
		})
		query_many_fn := ctx.js_function(fn [ctx, mut conn] (args []Value) Value {
			mut query_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if conn.closed {
				query_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			if args.len == 0 {
				query_err = mysql_error_value(ctx, 'sql is required', 'TypeError')
				unsafe {
					goto reject
				}
			}
			query_text := args[0].to_string()
			batches := mysql_param_batches(args, 1) or {
				query_err = mysql_error_value(ctx, err.msg(), 'TypeError')
				unsafe {
					goto reject
				}
				[][]HostMySqlParam{}
			}
			results := ctx.js_array()
				for i, params in batches {
					rows := mysql_query_maps_with_params(mut conn.db, query_text, params) or {
					results.free()
					query_err = mysql_error_value(ctx, err.msg(), 'Error')
					unsafe {
						goto reject
					}
					HostMySqlPreparedRows{}
				}
				rows_value := mysql_rows_value_from_maps(ctx, rows.rows)
				results.set(i, rows_value)
				rows_value.free()
			}
			return promise.resolve(results)
			reject:
			return promise.reject(query_err)
		})
		exec_fn := ctx.js_function(fn [ctx, mut conn] (args []Value) Value {
			mut exec_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if conn.closed {
				exec_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			if args.len == 0 {
				exec_err = mysql_error_value(ctx, 'sql is required', 'TypeError')
				unsafe {
					goto reject
				}
			}
			query_text := args[0].to_string()
			result := ctx.js_object()
			params := mysql_params(args, 1) or {
				exec_err = mysql_error_value(ctx, err.msg(), mysql_error_name_from_message(err.msg()))
				unsafe {
					goto reject
				}
				[]HostMySqlParam{}
			}
			mut exec_rows := HostMySqlPreparedRows{}
			mut changes := i64(0)
			mut rows_affected := i64(0)
			mut last_insert_id := i64(0)
			if params.len > 0 {
				exec_meta := mysql_exec_result_with_params(mut conn.db, query_text, params) or {
					exec_err = mysql_error_value(ctx, err.msg(), mysql_error_name_from_message(err.msg()))
					unsafe {
						goto reject
					}
					HostMySqlExecResult{}
				}
				exec_rows = HostMySqlPreparedRows{
					rows: exec_meta.rows
				}
				changes = exec_meta.changes
				rows_affected = exec_meta.rows_affected
				last_insert_id = exec_meta.last_insert_id
			} else {
				exec_rows = mysql_exec_maps(mut conn, query_text, args, 1) or {
					exec_err = mysql_error_value(ctx, err.msg(), mysql_error_name_from_message(err.msg()))
					unsafe {
						goto reject
					}
					HostMySqlPreparedRows{}
				}
				changes = i64(conn.db.affected_rows())
				rows_affected = i64(conn.db.affected_rows())
				last_insert_id = conn.db.last_id()
			}
			rows_value := mysql_rows_value_from_maps(ctx, exec_rows.rows)
			result.set('rows', rows_value)
			result.set('changes', changes)
			result.set('rowsAffected', rows_affected)
			result.set('lastInsertRowid', last_insert_id)
			result.set('insertId', last_insert_id)
			rows_value.free()
			return promise.resolve(result)
			reject:
			return promise.reject(exec_err)
		})
		exec_many_fn := ctx.js_function(fn [ctx, mut conn] (args []Value) Value {
			mut exec_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if conn.closed {
				exec_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			if args.len == 0 {
				exec_err = mysql_error_value(ctx, 'sql is required', 'TypeError')
				unsafe {
					goto reject
				}
			}
			query_text := args[0].to_string()
			batches := mysql_param_batches(args, 1) or {
				exec_err = mysql_error_value(ctx, err.msg(), 'TypeError')
				unsafe {
					goto reject
				}
				[][]HostMySqlParam{}
			}
			results := ctx.js_array()
			for i, params in batches {
				exec_meta := mysql_exec_result_with_params(mut conn.db, query_text, params) or {
					results.free()
					exec_err = mysql_error_value(ctx, err.msg(), 'Error')
					unsafe {
						goto reject
					}
					HostMySqlExecResult{}
				}
				result := ctx.js_object()
				rows_value := mysql_rows_value_from_maps(ctx, exec_meta.rows)
				result.set('rows', rows_value)
				result.set('changes', exec_meta.changes)
				result.set('rowsAffected', exec_meta.rows_affected)
				result.set('lastInsertRowid', exec_meta.last_insert_id)
				result.set('insertId', exec_meta.last_insert_id)
				rows_value.free()
				results.set(i, result)
				result.free()
			}
			return promise.resolve(results)
			reject:
			return promise.reject(exec_err)
		})
		close_fn := ctx.js_function(fn [ctx, mut conn, obj] (args []Value) Value {
			mut close_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if conn.closed {
				return promise.resolve(ctx.js_undefined())
			}
			mysql_close_conn_statements(mut conn)
			conn.db.close() or {
				close_err = mysql_error_value(ctx, err.msg(), 'Error')
				unsafe {
					goto reject
				}
			}
			conn.closed = true
			mysql_set_transaction_state(mut conn, obj, false)
			return promise.resolve(ctx.js_undefined())
			reject:
			return promise.reject(close_err)
		})
		ping_fn := ctx.js_function(fn [ctx, mut conn] (args []Value) Value {
			mut ping_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if conn.closed {
				ping_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			ok := conn.db.ping() or {
				ping_err = mysql_error_value(ctx, err.msg(), 'Error')
				unsafe {
					goto reject
				}
				false
			}
			return promise.resolve(ok)
			reject:
			return promise.reject(ping_err)
		})
		begin_fn := ctx.js_function(fn [ctx, mut conn, obj] (args []Value) Value {
			mut begin_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if conn.closed {
				begin_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			conn.db.exec('start transaction') or {
				begin_err = mysql_error_value(ctx, err.msg(), 'Error')
				unsafe {
					goto reject
				}
				[]vmysql.Row{}
			}
			mysql_set_transaction_state(mut conn, obj, true)
			return promise.resolve(ctx.js_undefined())
			reject:
			return promise.reject(begin_err)
		})
		commit_fn := ctx.js_function(fn [ctx, mut conn, obj] (args []Value) Value {
			mut commit_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if conn.closed {
				commit_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			conn.db.exec('commit') or {
				commit_err = mysql_error_value(ctx, err.msg(), 'Error')
				unsafe {
					goto reject
				}
				[]vmysql.Row{}
			}
			mysql_set_transaction_state(mut conn, obj, false)
			return promise.resolve(ctx.js_undefined())
			reject:
			return promise.reject(commit_err)
		})
		rollback_fn := ctx.js_function(fn [ctx, mut conn, obj] (args []Value) Value {
			mut rollback_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if conn.closed {
				rollback_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			conn.db.exec('rollback') or {
				rollback_err = mysql_error_value(ctx, err.msg(), 'Error')
				unsafe {
					goto reject
				}
				[]vmysql.Row{}
			}
			mysql_set_transaction_state(mut conn, obj, false)
			return promise.resolve(ctx.js_undefined())
			reject:
			return promise.reject(rollback_err)
		})
		transaction_fn := ctx.js_function(fn [ctx, mut conn, obj] (args []Value) Value {
			mut tx_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if conn.closed {
				tx_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			if args.len == 0 || !args[0].is_function() {
				tx_err = mysql_error_value(ctx, 'transaction callback is required', 'TypeError')
				unsafe {
					goto reject
				}
			}
			mysql_begin_transaction(mut conn) or {
				tx_err = mysql_error_value(ctx, err.msg(), 'Error')
				unsafe {
					goto reject
				}
			}
			mysql_set_transaction_state(mut conn, obj, true)
			callback_result := ctx.call(args[0], obj) or {
				tx_err = mysql_rollback_error_value(ctx, mut conn, err.msg())
				mysql_set_transaction_state(mut conn, obj, false)
				unsafe {
					goto reject
				}
				ctx.js_undefined()
			}
			mut resolved_result := callback_result
			if callback_result.instanceof('Promise') {
				ignore_rejection := ctx.js_function(fn [ctx] (args []Value) Value {
					return ctx.js_undefined()
				})
				callback_result.call('catch', ignore_rejection)
				resolved_result = ctx.js_await(callback_result) or {
					tx_err = mysql_rollback_error_value(ctx, mut conn, mysql_error_message(err))
					mysql_set_transaction_state(mut conn, obj, false)
					unsafe {
						goto reject
					}
					ctx.js_undefined()
				}
			}
			mysql_commit_transaction(mut conn) or {
				tx_err = mysql_rollback_error_value(ctx, mut conn, mysql_error_message(err))
				mysql_set_transaction_state(mut conn, obj, false)
				unsafe {
					goto reject
				}
			}
			mysql_set_transaction_state(mut conn, obj, false)
			return promise.resolve(resolved_result)
			reject:
			return promise.reject(tx_err)
		})
		prepare_fn := ctx.js_function(fn [ctx, mut conn] (args []Value) Value {
			mut prepare_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if conn.closed {
				prepare_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			if args.len == 0 || !args[0].is_string() {
				prepare_err = mysql_error_value(ctx, 'sql is required', 'TypeError')
				unsafe {
					goto reject
				}
			}
			mut stmt := &HostMySqlStmt{
				conn:       conn
				query_text: args[0].to_string()
				obj_ref:    ctx.js_undefined()
			}
			conn.stmts << stmt
			return promise.resolve(mysql_stmt_object(ctx, mut stmt))
			reject:
			return promise.reject(prepare_err)
		})
		prepare_cached_fn := ctx.js_function(fn [ctx, mut conn] (args []Value) Value {
			mut prepare_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if conn.closed {
				prepare_err = mysql_error_value(ctx, 'mysql connection is closed', 'Error')
				unsafe {
					goto reject
				}
			}
			if args.len == 0 || !args[0].is_string() {
				prepare_err = mysql_error_value(ctx, 'sql is required', 'TypeError')
				unsafe {
					goto reject
				}
			}
			query_text := args[0].to_string()
			if cached_stmt := conn.cached_stmts[query_text] {
				if !cached_stmt.closed {
					return promise.resolve(cached_stmt.obj_ref.dup_value())
				}
				conn.cached_stmts.delete(query_text)
			}
			mut stmt := &HostMySqlStmt{
				conn:       conn
				query_text: query_text
				obj_ref:    ctx.js_undefined()
				cache_key:  query_text
			}
			conn.stmts << stmt
			stmt_obj := mysql_stmt_object(ctx, mut stmt)
			conn.cached_stmts[query_text] = stmt
			return promise.resolve(stmt_obj)
			reject:
			return promise.reject(prepare_err)
		})
		obj.set('query', query_fn)
		obj.set('queryOne', query_one_fn)
		obj.set('scalar', scalar_fn)
		obj.set('queryMany', query_many_fn)
		obj.set('exec', exec_fn)
		obj.set('execMany', exec_many_fn)
		obj.set('close', close_fn)
		obj.set('ping', ping_fn)
		obj.set('begin', begin_fn)
		obj.set('commit', commit_fn)
		obj.set('rollback', rollback_fn)
		obj.set('transaction', transaction_fn)
		obj.set('prepare', prepare_fn)
		obj.set('prepareCached', prepare_cached_fn)
		obj.set('toString', to_string_fn)
		to_string_fn.free()
		query_fn.free()
		query_one_fn.free()
		scalar_fn.free()
		query_many_fn.free()
		exec_fn.free()
		exec_many_fn.free()
		close_fn.free()
		ping_fn.free()
		begin_fn.free()
		commit_fn.free()
		rollback_fn.free()
		transaction_fn.free()
		prepare_fn.free()
		prepare_cached_fn.free()
		return obj
	}

	pub fn (ctx &Context) install_mysql_module() {
		mut mysql_mod := ctx.js_module('mysql')
		connect_fn := ctx.js_function(fn [ctx] (args []Value) Value {
			mut connect_err := ctx.js_undefined()
			promise := ctx.js_promise()
			if args.len == 0 {
				connect_err = mysql_error_value(ctx, 'options object is required', 'TypeError')
				unsafe {
					goto reject
				}
			}
			config := mysql_connect_config(args[0]) or {
				connect_err = mysql_error_value(ctx, err.msg(), 'TypeError')
				unsafe {
					goto reject
				}
				HostMySqlConnectConfig{}
			}
			mut db := vmysql.connect(vmysql.Config{
				host:     config.host
				port:     config.port
				username: config.username
				password: config.password
				dbname:   config.dbname
			}) or {
				connect_err = mysql_error_value(ctx, err.msg(), 'Error')
				unsafe {
					goto reject
				}
				vmysql.DB{}
			}
			mut conn := &HostMySqlConn{
				db: db
			}
			ctx.register_host_cleanup(fn [mut conn] () {
				mysql_close_host_conn(mut conn)
			})
			return promise.resolve(mysql_conn_object(ctx, mut conn))
			reject:
			return promise.reject(connect_err)
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
