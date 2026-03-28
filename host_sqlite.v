module vjsx

import db.sqlite as vsqlite

@[heap]
struct HostSqliteConn {
mut:
	db           vsqlite.DB
	closed       bool
	in_tx        bool
	path         string
	stmts        []&HostSqliteStmt
	cached_stmts map[string]&HostSqliteStmt
}

struct HostSqliteOpenConfig {
	path         string
	busy_timeout int
}

@[heap]
struct HostSqliteStmt {
mut:
	conn       &HostSqliteConn = unsafe { nil }
	query_text string
	closed     bool
	obj_ref    Value
	cache_key  string
}

fn sql_stmt_kind(query_text string) string {
	head := query_text.trim_space().to_lower()
	if head.starts_with('select ') || head.starts_with('with ') || head.starts_with('pragma ')
		|| head.starts_with('show ') || head.starts_with('describe ') || head.starts_with('explain ') {
		return 'query'
	}
	if head.starts_with('insert ') || head.starts_with('update ') || head.starts_with('delete ')
		|| head.starts_with('replace ') || head.starts_with('create ') || head.starts_with('drop ')
		|| head.starts_with('alter ') || head.starts_with('begin ') || head.starts_with('commit')
		|| head.starts_with('rollback') || head.starts_with('start transaction') {
		return 'exec'
	}
	return 'unknown'
}

fn sqlite_error_value(ctx &Context, message string, name string) Value {
	return ctx.js_error(
		message: message
		name:    name
	)
}

fn sqlite_error_message(err IError) string {
	line := err.msg().split_into_lines()[0]
	if idx := line.index(': ') {
		prefix := line[..idx]
		if prefix.ends_with('Error') {
			return line[idx + 2..]
		}
	}
	return line
}

fn sqlite_begin_transaction(mut conn HostSqliteConn) ! {
	conn.db.exec('begin transaction')!
}

fn sqlite_commit_transaction(mut conn HostSqliteConn) ! {
	conn.db.exec('commit')!
}

fn sqlite_rollback_transaction(mut conn HostSqliteConn) ! {
	conn.db.exec('rollback')!
}

fn sqlite_rollback_error_value(ctx &Context, mut conn HostSqliteConn, fallback_message string) Value {
	sqlite_rollback_transaction(mut conn) or {
		return sqlite_error_value(ctx, sqlite_error_message(err), 'Error')
	}
	return sqlite_error_value(ctx, fallback_message, 'Error')
}

fn sqlite_set_transaction_state(mut conn HostSqliteConn, conn_obj Value, active bool) {
	conn.in_tx = active
	conn_obj.set('inTransaction', active)
}

fn sqlite_mark_stmt_closed(mut stmt HostSqliteStmt) {
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

fn sqlite_close_conn_statements(mut conn HostSqliteConn) {
	for mut stmt in conn.stmts {
		sqlite_mark_stmt_closed(mut stmt)
	}
	conn.cached_stmts = map[string]&HostSqliteStmt{}
}

fn sqlite_rows_value(ctx &Context, rows []vsqlite.Row) Value {
	arr := ctx.js_array()
	for i, row in rows {
		obj := sqlite_row_value(ctx, row)
		arr.set(i, obj)
		obj.free()
	}
	return arr
}

fn sqlite_row_value(ctx &Context, row vsqlite.Row) Value {
	obj := ctx.js_object()
	for j, name in row.names {
		obj.set(name, if j < row.vals.len { row.vals[j] } else { '' })
	}
	return obj
}

fn sqlite_first_row_value(ctx &Context, rows []vsqlite.Row) Value {
	if rows.len == 0 {
		return ctx.js_null()
	}
	return sqlite_row_value(ctx, rows[0])
}

fn sqlite_first_scalar_value(ctx &Context, rows []vsqlite.Row) Value {
	if rows.len == 0 || rows[0].vals.len == 0 {
		return ctx.js_null()
	}
	return ctx.js_string(rows[0].vals[0])
}

fn sqlite_query_rows(mut conn HostSqliteConn, query_text string, params []string) ![]vsqlite.Row {
	return if params.len > 0 {
		conn.db.exec_param_many(query_text, params)!
	} else {
		conn.db.exec(query_text)!
	}
}

fn sqlite_exec_result_value(ctx &Context, rows []vsqlite.Row, changes int, last_insert_rowid i64) Value {
	result := ctx.js_object()
	rows_value := sqlite_rows_value(ctx, rows)
	result.set('rows', rows_value)
	result.set('changes', changes)
	result.set('rowsAffected', changes)
	result.set('lastInsertRowid', last_insert_rowid)
	result.set('insertId', last_insert_rowid)
	rows_value.free()
	return result
}

fn sqlite_value_param(arg Value) string {
	if arg.is_null() || arg.is_undefined() {
		return ''
	}
	return arg.to_string()
}

fn sqlite_params(args []Value, index int) ![]string {
	if index >= args.len || args[index].is_undefined() || args[index].is_null() {
		return []string{}
	}
	if !args[index].is_array() {
		return error('params must be an array')
	}
	length_value := args[index].get('length')
	defer {
		length_value.free()
	}
	length := length_value.to_int()
	mut params := []string{cap: length}
	for i in 0 .. length {
		value := args[index].get(i)
		params << sqlite_value_param(value)
		value.free()
	}
	return params
}

fn sqlite_param_batches(args []Value, index int) ![][]string {
	if index >= args.len || args[index].is_undefined() || args[index].is_null() {
		return [][]string{}
	}
	if !args[index].is_array() {
		return error('param batches must be an array')
	}
	length_value := args[index].get('length')
	defer {
		length_value.free()
	}
	batch_len := length_value.to_int()
	mut batches := [][]string{cap: batch_len}
	for i in 0 .. batch_len {
		batch_value := args[index].get(i)
		if !batch_value.is_array() {
			batch_value.free()
			return error('each param batch must be an array')
		}
		params_len_value := batch_value.get('length')
		params_len := params_len_value.to_int()
		params_len_value.free()
		mut params := []string{cap: params_len}
		for j in 0 .. params_len {
			param_value := batch_value.get(j)
			params << sqlite_value_param(param_value)
			param_value.free()
		}
		batch_value.free()
		batches << params
	}
	return batches
}

fn sqlite_open_config(arg Value) !HostSqliteOpenConfig {
	if arg.is_string() {
		return HostSqliteOpenConfig{
			path: arg.to_string()
		}
	}
	if !arg.is_object() {
		return error('path or options object is required')
	}
	path_value := arg.get('path')
	defer {
		path_value.free()
	}
	if path_value.is_undefined() || path_value.is_null() || !path_value.is_string() {
		return error('options.path must be a string')
	}
	busy_value := arg.get('busyTimeout')
	defer {
		busy_value.free()
	}
	if !busy_value.is_undefined() && !busy_value.is_null() && !busy_value.is_number() {
		return error('options.busyTimeout must be a number')
	}
	return HostSqliteOpenConfig{
		path:         path_value.to_string()
		busy_timeout: if busy_value.is_undefined() || busy_value.is_null() { 0 } else { busy_value.to_int() }
	}
}

fn sqlite_stmt_object(ctx &Context, mut stmt HostSqliteStmt) Value {
	obj := ctx.js_object()
	obj.set('driver', 'sqlite')
	obj.set('supportsTransactions', true)
	obj.set('sql', stmt.query_text)
	obj.set('kind', sql_stmt_kind(stmt.query_text))
	obj.set('closed', stmt.closed)
	stmt.obj_ref = obj.dup_value()
	to_string_fn := ctx.js_function(fn [ctx, stmt] (args []Value) Value {
		return ctx.js_string('sqlite.Statement{kind: ${sql_stmt_kind(stmt.query_text)}, closed: ${stmt.closed}, sql: ${stmt.query_text}}')
	})
	query_fn := ctx.js_function(fn [ctx, mut stmt] (args []Value) Value {
		mut query_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if stmt.closed {
			query_err = sqlite_error_value(ctx, 'sqlite statement is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		if stmt.conn.closed {
			query_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		params := sqlite_params(args, 0) or {
			query_err = sqlite_error_value(ctx, err.msg(), 'TypeError')
			unsafe {
				goto reject
			}
			[]string{}
		}
		rows := sqlite_query_rows(mut stmt.conn, stmt.query_text, params) or {
			query_err = sqlite_error_value(ctx, err.msg(), 'Error')
			unsafe {
				goto reject
			}
			[]vsqlite.Row{}
		}
		return promise.resolve(sqlite_rows_value(ctx, rows))
		reject:
		return promise.reject(query_err)
	})
	query_one_fn := ctx.js_function(fn [ctx, mut stmt] (args []Value) Value {
		mut query_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if stmt.closed {
			query_err = sqlite_error_value(ctx, 'sqlite statement is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		if stmt.conn.closed {
			query_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		params := sqlite_params(args, 0) or {
			query_err = sqlite_error_value(ctx, err.msg(), 'TypeError')
			unsafe {
				goto reject
			}
			[]string{}
		}
		rows := sqlite_query_rows(mut stmt.conn, stmt.query_text, params) or {
			query_err = sqlite_error_value(ctx, err.msg(), 'Error')
			unsafe {
				goto reject
			}
			[]vsqlite.Row{}
		}
		return promise.resolve(sqlite_first_row_value(ctx, rows))
		reject:
		return promise.reject(query_err)
	})
	scalar_fn := ctx.js_function(fn [ctx, mut stmt] (args []Value) Value {
		mut query_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if stmt.closed {
			query_err = sqlite_error_value(ctx, 'sqlite statement is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		if stmt.conn.closed {
			query_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		params := sqlite_params(args, 0) or {
			query_err = sqlite_error_value(ctx, err.msg(), 'TypeError')
			unsafe {
				goto reject
			}
			[]string{}
		}
		rows := sqlite_query_rows(mut stmt.conn, stmt.query_text, params) or {
			query_err = sqlite_error_value(ctx, err.msg(), 'Error')
			unsafe {
				goto reject
			}
			[]vsqlite.Row{}
		}
		return promise.resolve(sqlite_first_scalar_value(ctx, rows))
		reject:
		return promise.reject(query_err)
	})
	query_many_fn := ctx.js_function(fn [ctx, mut stmt] (args []Value) Value {
		mut query_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if stmt.closed {
			query_err = sqlite_error_value(ctx, 'sqlite statement is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		if stmt.conn.closed {
			query_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		batches := sqlite_param_batches(args, 0) or {
			query_err = sqlite_error_value(ctx, err.msg(), 'TypeError')
			unsafe {
				goto reject
			}
			[][]string{}
		}
		results := ctx.js_array()
		for i, params in batches {
			rows := sqlite_query_rows(mut stmt.conn, stmt.query_text, params) or {
				results.free()
				query_err = sqlite_error_value(ctx, err.msg(), 'Error')
				unsafe {
					goto reject
				}
				[]vsqlite.Row{}
			}
			rows_value := sqlite_rows_value(ctx, rows)
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
			exec_err = sqlite_error_value(ctx, 'sqlite statement is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		if stmt.conn.closed {
			exec_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		params := sqlite_params(args, 0) or {
			exec_err = sqlite_error_value(ctx, err.msg(), 'TypeError')
			unsafe {
				goto reject
			}
			[]string{}
		}
		rows := sqlite_query_rows(mut stmt.conn, stmt.query_text, params) or {
			exec_err = sqlite_error_value(ctx, err.msg(), 'Error')
			unsafe {
				goto reject
			}
			[]vsqlite.Row{}
		}
		return promise.resolve(sqlite_exec_result_value(ctx, rows, stmt.conn.db.get_affected_rows_count(),
			stmt.conn.db.last_insert_rowid()))
		reject:
		return promise.reject(exec_err)
	})
	exec_many_fn := ctx.js_function(fn [ctx, mut stmt] (args []Value) Value {
		mut exec_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if stmt.closed {
			exec_err = sqlite_error_value(ctx, 'sqlite statement is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		if stmt.conn.closed {
			exec_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		batches := sqlite_param_batches(args, 0) or {
			exec_err = sqlite_error_value(ctx, err.msg(), 'TypeError')
			unsafe {
				goto reject
			}
			[][]string{}
		}
		results := ctx.js_array()
		for i, params in batches {
			rows := sqlite_query_rows(mut stmt.conn, stmt.query_text, params) or {
				results.free()
				exec_err = sqlite_error_value(ctx, err.msg(), 'Error')
				unsafe {
					goto reject
				}
				[]vsqlite.Row{}
			}
			result := sqlite_exec_result_value(ctx, rows, stmt.conn.db.get_affected_rows_count(),
				stmt.conn.db.last_insert_rowid())
			results.set(i, result)
			result.free()
		}
		return promise.resolve(results)
		reject:
		return promise.reject(exec_err)
	})
	close_fn := ctx.js_function(fn [ctx, mut stmt] (args []Value) Value {
		promise := ctx.js_promise()
		sqlite_mark_stmt_closed(mut stmt)
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

fn sqlite_conn_object(ctx &Context, mut conn HostSqliteConn) Value {
	obj := ctx.js_object()
	obj.set('driver', 'sqlite')
	obj.set('supportsTransactions', true)
	obj.set('path', conn.path)
	obj.set('inTransaction', conn.in_tx)
	to_string_fn := ctx.js_function(fn [ctx, conn] (args []Value) Value {
		return ctx.js_string('sqlite.Connection{path: ${conn.path}, closed: ${conn.closed}, inTransaction: ${conn.in_tx}}')
	})
	query_fn := ctx.js_function(fn [ctx, mut conn] (args []Value) Value {
		mut query_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if conn.closed {
			query_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		if args.len == 0 {
			query_err = sqlite_error_value(ctx, 'sql is required', 'TypeError')
			unsafe {
				goto reject
			}
		}
		query_text := args[0].to_string()
		params := sqlite_params(args, 1) or {
			query_err = sqlite_error_value(ctx, err.msg(), 'TypeError')
			unsafe {
				goto reject
			}
			[]string{}
		}
		rows := sqlite_query_rows(mut conn, query_text, params) or {
			query_err = sqlite_error_value(ctx, err.msg(), 'Error')
			unsafe {
				goto reject
			}
			[]vsqlite.Row{}
		}
		return promise.resolve(sqlite_rows_value(ctx, rows))
		reject:
		return promise.reject(query_err)
	})
	query_one_fn := ctx.js_function(fn [ctx, mut conn] (args []Value) Value {
		mut query_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if conn.closed {
			query_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		if args.len == 0 {
			query_err = sqlite_error_value(ctx, 'sql is required', 'TypeError')
			unsafe {
				goto reject
			}
		}
		query_text := args[0].to_string()
		params := sqlite_params(args, 1) or {
			query_err = sqlite_error_value(ctx, err.msg(), 'TypeError')
			unsafe {
				goto reject
			}
			[]string{}
		}
		rows := sqlite_query_rows(mut conn, query_text, params) or {
			query_err = sqlite_error_value(ctx, err.msg(), 'Error')
			unsafe {
				goto reject
			}
			[]vsqlite.Row{}
		}
		return promise.resolve(sqlite_first_row_value(ctx, rows))
		reject:
		return promise.reject(query_err)
	})
	scalar_fn := ctx.js_function(fn [ctx, mut conn] (args []Value) Value {
		mut query_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if conn.closed {
			query_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		if args.len == 0 {
			query_err = sqlite_error_value(ctx, 'sql is required', 'TypeError')
			unsafe {
				goto reject
			}
		}
		query_text := args[0].to_string()
		params := sqlite_params(args, 1) or {
			query_err = sqlite_error_value(ctx, err.msg(), 'TypeError')
			unsafe {
				goto reject
			}
			[]string{}
		}
		rows := sqlite_query_rows(mut conn, query_text, params) or {
			query_err = sqlite_error_value(ctx, err.msg(), 'Error')
			unsafe {
				goto reject
			}
			[]vsqlite.Row{}
		}
		return promise.resolve(sqlite_first_scalar_value(ctx, rows))
		reject:
		return promise.reject(query_err)
	})
	query_many_fn := ctx.js_function(fn [ctx, mut conn] (args []Value) Value {
		mut query_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if conn.closed {
			query_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		if args.len == 0 {
			query_err = sqlite_error_value(ctx, 'sql is required', 'TypeError')
			unsafe {
				goto reject
			}
		}
		query_text := args[0].to_string()
		batches := sqlite_param_batches(args, 1) or {
			query_err = sqlite_error_value(ctx, err.msg(), 'TypeError')
			unsafe {
				goto reject
			}
			[][]string{}
		}
		results := ctx.js_array()
		for i, params in batches {
			rows := sqlite_query_rows(mut conn, query_text, params) or {
				results.free()
				query_err = sqlite_error_value(ctx, err.msg(), 'Error')
				unsafe {
					goto reject
				}
				[]vsqlite.Row{}
			}
			rows_value := sqlite_rows_value(ctx, rows)
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
			exec_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		if args.len == 0 {
			exec_err = sqlite_error_value(ctx, 'sql is required', 'TypeError')
			unsafe {
				goto reject
			}
		}
		query_text := args[0].to_string()
		params := sqlite_params(args, 1) or {
			exec_err = sqlite_error_value(ctx, err.msg(), 'TypeError')
			unsafe {
				goto reject
			}
			[]string{}
		}
		rows := sqlite_query_rows(mut conn, query_text, params) or {
			exec_err = sqlite_error_value(ctx, err.msg(), 'Error')
			unsafe {
				goto reject
			}
			[]vsqlite.Row{}
		}
		return promise.resolve(sqlite_exec_result_value(ctx, rows, conn.db.get_affected_rows_count(),
			conn.db.last_insert_rowid()))
		reject:
		return promise.reject(exec_err)
	})
	exec_many_fn := ctx.js_function(fn [ctx, mut conn] (args []Value) Value {
		mut exec_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if conn.closed {
			exec_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		if args.len == 0 {
			exec_err = sqlite_error_value(ctx, 'sql is required', 'TypeError')
			unsafe {
				goto reject
			}
		}
		query_text := args[0].to_string()
		batches := sqlite_param_batches(args, 1) or {
			exec_err = sqlite_error_value(ctx, err.msg(), 'TypeError')
			unsafe {
				goto reject
			}
			[][]string{}
		}
		results := ctx.js_array()
		for i, params in batches {
			rows := sqlite_query_rows(mut conn, query_text, params) or {
				results.free()
				exec_err = sqlite_error_value(ctx, err.msg(), 'Error')
				unsafe {
					goto reject
				}
				[]vsqlite.Row{}
			}
			result := sqlite_exec_result_value(ctx, rows, conn.db.get_affected_rows_count(),
				conn.db.last_insert_rowid())
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
		conn.db.close() or {
			close_err = sqlite_error_value(ctx, err.msg(), 'Error')
			unsafe {
				goto reject
			}
		}
		sqlite_close_conn_statements(mut conn)
		conn.closed = true
		sqlite_set_transaction_state(mut conn, obj, false)
		return promise.resolve(ctx.js_undefined())
		reject:
		return promise.reject(close_err)
	})
	begin_fn := ctx.js_function(fn [ctx, mut conn, obj] (args []Value) Value {
		mut begin_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if conn.closed {
			begin_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		conn.db.exec('begin transaction') or {
			begin_err = sqlite_error_value(ctx, err.msg(), 'Error')
			unsafe {
				goto reject
			}
		}
		sqlite_set_transaction_state(mut conn, obj, true)
		return promise.resolve(ctx.js_undefined())
		reject:
		return promise.reject(begin_err)
	})
	commit_fn := ctx.js_function(fn [ctx, mut conn, obj] (args []Value) Value {
		mut commit_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if conn.closed {
			commit_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		conn.db.exec('commit') or {
			commit_err = sqlite_error_value(ctx, err.msg(), 'Error')
			unsafe {
				goto reject
			}
		}
		sqlite_set_transaction_state(mut conn, obj, false)
		return promise.resolve(ctx.js_undefined())
		reject:
		return promise.reject(commit_err)
	})
	rollback_fn := ctx.js_function(fn [ctx, mut conn, obj] (args []Value) Value {
		mut rollback_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if conn.closed {
			rollback_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		conn.db.exec('rollback') or {
			rollback_err = sqlite_error_value(ctx, err.msg(), 'Error')
			unsafe {
				goto reject
			}
		}
		sqlite_set_transaction_state(mut conn, obj, false)
		return promise.resolve(ctx.js_undefined())
		reject:
		return promise.reject(rollback_err)
	})
	transaction_fn := ctx.js_function(fn [ctx, mut conn, obj] (args []Value) Value {
		mut tx_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if conn.closed {
			tx_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
			if args.len == 0 || !args[0].is_function() {
				tx_err = sqlite_error_value(ctx, 'transaction callback is required', 'TypeError')
				unsafe {
				goto reject
			}
		}
			sqlite_begin_transaction(mut conn) or {
				tx_err = sqlite_error_value(ctx, err.msg(), 'Error')
				unsafe {
					goto reject
				}
			}
			sqlite_set_transaction_state(mut conn, obj, true)
			callback_result := ctx.call(args[0], obj) or {
				tx_err = sqlite_rollback_error_value(ctx, mut conn, err.msg())
				sqlite_set_transaction_state(mut conn, obj, false)
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
					tx_err = sqlite_rollback_error_value(ctx, mut conn, sqlite_error_message(err))
					sqlite_set_transaction_state(mut conn, obj, false)
					unsafe {
						goto reject
					}
				ctx.js_undefined()
			}
			}
			sqlite_commit_transaction(mut conn) or {
				tx_err = sqlite_rollback_error_value(ctx, mut conn, sqlite_error_message(err))
				sqlite_set_transaction_state(mut conn, obj, false)
				unsafe {
					goto reject
				}
			}
			sqlite_set_transaction_state(mut conn, obj, false)
			return promise.resolve(resolved_result)
			reject:
			return promise.reject(tx_err)
	})
	prepare_fn := ctx.js_function(fn [ctx, mut conn] (args []Value) Value {
		mut prepare_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if conn.closed {
			prepare_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		if args.len == 0 || !args[0].is_string() {
			prepare_err = sqlite_error_value(ctx, 'sql is required', 'TypeError')
			unsafe {
				goto reject
			}
		}
		mut stmt := &HostSqliteStmt{
			conn:       conn
			query_text: args[0].to_string()
			obj_ref:    ctx.js_undefined()
		}
		conn.stmts << stmt
		return promise.resolve(sqlite_stmt_object(ctx, mut stmt))
		reject:
		return promise.reject(prepare_err)
	})
	prepare_cached_fn := ctx.js_function(fn [ctx, mut conn] (args []Value) Value {
		mut prepare_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if conn.closed {
			prepare_err = sqlite_error_value(ctx, 'sqlite connection is closed', 'Error')
			unsafe {
				goto reject
			}
		}
		if args.len == 0 || !args[0].is_string() {
			prepare_err = sqlite_error_value(ctx, 'sql is required', 'TypeError')
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
		mut stmt := &HostSqliteStmt{
			conn:       conn
			query_text: query_text
			obj_ref:    ctx.js_undefined()
			cache_key:  query_text
		}
		conn.stmts << stmt
		stmt_obj := sqlite_stmt_object(ctx, mut stmt)
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
	begin_fn.free()
	commit_fn.free()
	rollback_fn.free()
	transaction_fn.free()
	prepare_fn.free()
	prepare_cached_fn.free()
	return obj
}

// Install a small `sqlite` host module with Promise-based open/query/exec helpers.
pub fn (ctx &Context) install_sqlite_module(roots []string) {
	mut sqlite_mod := ctx.js_module('sqlite')
	open_fn := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		mut open_err := ctx.js_undefined()
		promise := ctx.js_promise()
		if args.len == 0 {
			open_err = sqlite_error_value(ctx, 'path or options object is required', 'TypeError')
			unsafe {
				goto reject
			}
		}
		config := sqlite_open_config(args[0]) or {
			open_err = sqlite_error_value(ctx, err.msg(), 'TypeError')
			unsafe {
				goto reject
			}
			HostSqliteOpenConfig{}
		}
		if config.path == '' {
			open_err = sqlite_error_value(ctx, 'path is required', 'TypeError')
			unsafe {
				goto reject
			}
		}
		target := if config.path == ':memory:' { config.path } else { write_target_path(config.path, roots) }
		mut db := vsqlite.connect(target) or {
			open_err = sqlite_error_value(ctx, err.msg(), 'Error')
			unsafe {
				goto reject
			}
			vsqlite.DB{}
		}
		if config.busy_timeout > 0 {
			db.busy_timeout(config.busy_timeout)
		}
		mut conn := &HostSqliteConn{
			db:   db
			path: target
		}
		return promise.resolve(sqlite_conn_object(ctx, mut conn))
		reject:
		return promise.reject(open_err)
	})
	sqlite_mod.export('open', open_fn)
	default_obj := ctx.js_object()
	default_obj.set('open', open_fn)
	sqlite_mod.export_default(default_obj)
	sqlite_mod.create()
	default_obj.free()
	open_fn.free()
}
