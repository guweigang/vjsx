module vjsx

$if vjsx_sqlite ? {
	fn C.sqlite3_open_v2(&char, &&C.sqlite3, int, &char) int
	fn C.sqlite3_close(&C.sqlite3) int
	fn C.sqlite3_busy_timeout(&C.sqlite3, int) int
	fn C.sqlite3_errmsg(&C.sqlite3) &char
	fn C.sqlite3_exec(&C.sqlite3, &char, voidptr, voidptr, voidptr) int
	fn C.sqlite3_prepare_v2(&C.sqlite3, &char, int, &&C.sqlite3_stmt, &&char) int
	fn C.sqlite3_finalize(&C.sqlite3_stmt) int
	fn C.sqlite3_step(&C.sqlite3_stmt) int
	fn C.sqlite3_bind_parameter_count(&C.sqlite3_stmt) int
	fn C.sqlite3_bind_null(&C.sqlite3_stmt, int) int
	fn C.sqlite3_bind_int64(&C.sqlite3_stmt, int, i64) int
	fn C.sqlite3_bind_double(&C.sqlite3_stmt, int, f64) int
	fn C.sqlite3_bind_text(&C.sqlite3_stmt, int, &char, int, voidptr) int
	fn C.sqlite3_bind_blob(&C.sqlite3_stmt, int, voidptr, int, voidptr) int
	fn C.sqlite3_bind_zeroblob(&C.sqlite3_stmt, int, int) int
	fn C.sqlite3_column_count(&C.sqlite3_stmt) int
	fn C.sqlite3_column_name(&C.sqlite3_stmt, int) &char
	fn C.sqlite3_column_type(&C.sqlite3_stmt, int) int
	fn C.sqlite3_column_int64(&C.sqlite3_stmt, int) i64
	fn C.sqlite3_column_double(&C.sqlite3_stmt, int) f64
	fn C.sqlite3_column_text(&C.sqlite3_stmt, int) &u8
	fn C.sqlite3_column_blob(&C.sqlite3_stmt, int) voidptr
	fn C.sqlite3_column_bytes(&C.sqlite3_stmt, int) int
	fn C.sqlite3_changes64(&C.sqlite3) i64
	fn C.sqlite3_last_insert_rowid(&C.sqlite3) i64
	fn C.JS_NewStringLen(&C.JSContext, &char, uint) C.JSValue
	fn C.JS_NewObjectProto(&C.JSContext, JSValueConst) C.JSValue

	const sqlite_max_safe_integer = i64(9007199254740991)

	@[heap]
	struct NodeSqliteConnection {
	mut:
		db &C.sqlite3 = unsafe { nil }
	}

	fn node_sqlite_error(db &C.sqlite3) IError {
		return error(unsafe { cstring_to_vstring(C.sqlite3_errmsg(db)) }.clone())
	}

	fn (mut conn NodeSqliteConnection) close() ! {
		if conn.db != unsafe { nil } {
			if C.sqlite3_close(conn.db) != C.SQLITE_OK {
				return node_sqlite_error(conn.db)
			}
			conn.db = unsafe { nil }
		}
	}

	fn node_sqlite_bind(stmt &C.sqlite3_stmt, index int, value Value) !int {
		if value.is_null() {
			return C.sqlite3_bind_null(stmt, index)
		}
		if value.is_big_int() {
			text := value.str()
			number := text.i64()
			if number.str() != text {
				return error('SQLite bigint parameter is outside the signed 64-bit range')
			}
			return C.sqlite3_bind_int64(stmt, index, number)
		}
		if value.is_number() {
			return C.sqlite3_bind_double(stmt, index, value.to_f64())
		}
		if value.is_string() {
			mut length := uint(0)
			data := C.JS_ToCStringLen(value.ctx.ref, &length, value.ref)
			if data == unsafe { nil } {
				return error('cannot encode SQLite text parameter')
			}
			defer {
				C.JS_FreeCString(value.ctx.ref, data)
			}
			if length > 2147483647 {
				return error('SQLite text parameter is too large')
			}
			return C.sqlite3_bind_text(stmt, index, data, int(length), voidptr(C.SQLITE_TRANSIENT))
		}
		if value.instanceof('Uint8Array') {
			bytes := fs_value_to_bytes(value)!
			if bytes.len == 0 {
				return C.sqlite3_bind_zeroblob(stmt, index, 0)
			}
			return C.sqlite3_bind_blob(stmt, index, bytes.data, bytes.len, voidptr(C.SQLITE_TRANSIENT))
		}
		return error('unsupported SQLite parameter type')
	}

	fn node_sqlite_integer(ctx &Context, value i64, big_ints bool) !Value {
		if big_ints {
			return ctx.js_big_int(value)
		}
		if value > sqlite_max_safe_integer || value < -sqlite_max_safe_integer {
			return error('SQLite integer is outside the JavaScript safe range; use setReadBigInts(true)')
		}
		return ctx.js_i64(value)
	}

	fn node_sqlite_column(ctx &Context, stmt &C.sqlite3_stmt, index int, big_ints bool) !Value {
		return match C.sqlite3_column_type(stmt, index) {
			C.SQLITE_INTEGER {
				node_sqlite_integer(ctx, C.sqlite3_column_int64(stmt, index), big_ints)!
			}
			C.SQLITE_FLOAT { ctx.js_float(C.sqlite3_column_double(stmt, index)) }
			C.SQLITE_TEXT {
				data := C.sqlite3_column_text(stmt, index)
				if data == unsafe { nil } {
					return error('cannot read SQLite text column')
				}
				ctx.c_val(C.JS_NewStringLen(ctx.ref, &char(data), uint(C.sqlite3_column_bytes(stmt, index))))
			}
			C.SQLITE_BLOB {
				data := C.sqlite3_column_blob(stmt, index)
				size := C.sqlite3_column_bytes(stmt, index)
				buffer := ctx.c_val(C.JS_NewArrayBufferCopy(ctx.ref, unsafe { &u8(data) }, uint(size)))
				defer {
					buffer.free()
				}
				constructor := ctx.js_global('Uint8Array')
				defer {
					constructor.free()
				}
				ctx.js_new_class(constructor, buffer)!
			}
			else { ctx.js_null() }
		}
	}

	fn node_sqlite_row(ctx &Context, stmt &C.sqlite3_stmt, big_ints bool) !Value {
		row := ctx.c_val(C.JS_NewObjectProto(ctx.ref, ctx.js_null().ref))
		for index in 0 .. C.sqlite3_column_count(stmt) {
			name := unsafe { cstring_to_vstring(C.sqlite3_column_name(stmt, index)) }
			value := node_sqlite_column(ctx, stmt, index, big_ints) or {
				row.free()
				return err
			}
			row.set(name, value)
			value.free()
		}
		return row
	}

	fn (conn &NodeSqliteConnection) execute(ctx &Context, args []Value) !Value {
		if conn.db == unsafe { nil } {
			return error('SQLite database is closed')
		}
		operation := args[0].str()
		sql := args[1].str()
		if operation == 'exec' {
			if C.sqlite3_exec(conn.db, &char(sql.str), unsafe { nil }, unsafe { nil }, unsafe { nil }) != C.SQLITE_OK {
				return node_sqlite_error(conn.db)
			}
			return ctx.js_undefined()
		}

		mut stmt := &C.sqlite3_stmt(unsafe { nil })
		mut tail := &char(unsafe { nil })
		if C.sqlite3_prepare_v2(conn.db, &char(sql.str), sql.len + 1, &stmt, &tail) != C.SQLITE_OK {
			return node_sqlite_error(conn.db)
		}
		if stmt == unsafe { nil } {
			return error('SQLite statement is empty')
		}
		defer {
			C.sqlite3_finalize(stmt)
		}
		if unsafe { cstring_to_vstring(tail) }.trim_space() != '' {
			mut extra := &C.sqlite3_stmt(unsafe { nil })
			status := C.sqlite3_prepare_v2(conn.db, tail, -1, &extra, unsafe { nil })
			if extra != unsafe { nil } {
				C.sqlite3_finalize(extra)
			}
			if status != C.SQLITE_OK || extra != unsafe { nil } {
				return error('prepare expects one SQLite statement; use exec for SQL scripts')
			}
		}
		if operation == 'prepare' {
			return ctx.js_undefined()
		}

		big_ints := args[2].to_bool()
		parameters := args[3..]
		for index in 1 .. C.sqlite3_bind_parameter_count(stmt) + 1 {
			if index > parameters.len {
				break
			}
			if node_sqlite_bind(stmt, index, parameters[index - 1])! != C.SQLITE_OK {
				return node_sqlite_error(conn.db)
			}
		}
		if parameters.len > C.sqlite3_bind_parameter_count(stmt) {
			return error('too many SQLite parameters')
		}
		mut status := C.sqlite3_step(stmt)
		if operation == 'get' && status == C.SQLITE_ROW {
			return node_sqlite_row(ctx, stmt, big_ints)
		}
		rows := if operation == 'all' { ctx.js_array() } else { ctx.js_undefined() }
		mut index := 0
		for status == C.SQLITE_ROW {
			if operation == 'all' {
				row := node_sqlite_row(ctx, stmt, big_ints) or {
					rows.free()
					return err
				}
				rows.set(index, row)
				row.free()
				index++
			}
			status = C.sqlite3_step(stmt)
		}
		if status != C.SQLITE_DONE {
			rows.free()
			return node_sqlite_error(conn.db)
		}
		if operation != 'run' {
			return rows
		}
		changes := node_sqlite_integer(ctx, C.sqlite3_changes64(conn.db), big_ints)!
		defer {
			changes.free()
		}
		last_insert_id := node_sqlite_integer(ctx, C.sqlite3_last_insert_rowid(conn.db), big_ints)!
		defer {
			last_insert_id.free()
		}
		result := ctx.js_object()
		result.set('changes', changes)
		result.set('lastInsertRowid', last_insert_id)
		return result
	}

	fn (ctx &Context) open_node_sqlite(roots []string, path string, read_only bool, timeout int) !Value {
		target := if path == ':memory:' || path == '' {
			path
		} else {
			write_target_path(path, roots)
		}
		flags := if read_only {
			C.SQLITE_OPEN_READONLY
		} else {
			C.SQLITE_OPEN_READWRITE | C.SQLITE_OPEN_CREATE
		}
		mut db := &C.sqlite3(unsafe { nil })
		status := C.sqlite3_open_v2(&char(target.str), &db, flags, unsafe { nil })
		if db == unsafe { nil } {
			return error('cannot allocate SQLite connection')
		}
		if status != C.SQLITE_OK || C.sqlite3_busy_timeout(db, timeout) != C.SQLITE_OK
			|| C.sqlite3_exec(db, c'PRAGMA foreign_keys = ON', unsafe { nil }, unsafe { nil }, unsafe { nil }) != C.SQLITE_OK {
			err := node_sqlite_error(db)
			C.sqlite3_close(db)
			return err
		}
		mut conn := &NodeSqliteConnection{ db: db }
		ctx.register_host_cleanup(fn [mut conn] () {
			conn.close() or {}
		})
		execute := ctx.js_function(fn [ctx, conn] (args []Value) Value {
			return conn.execute(ctx, args) or { ctx.js_throw(ctx.js_error(message: err.msg())) }
		})
		close := ctx.js_function(fn [ctx, mut conn] (args []Value) Value {
			conn.close() or { return ctx.js_throw(ctx.js_error(message: err.msg())) }
			return ctx.js_undefined()
		})
		handle := ctx.js_object()
		handle.set('execute', execute)
		handle.set('close', close)
		execute.free()
		close.free()
		return handle
	}

	fn (ctx &Context) install_node_sqlite_module(roots []string) ! {
		factory := ctx.eval($embed_file('web/js/node_sqlite.js').to_string())!
		defer {
			factory.free()
		}
		open := ctx.js_function(fn [ctx, roots] (args []Value) Value {
			return ctx.open_node_sqlite(roots, args[0].str(), args[1].to_bool(), args[2].to_int()) or {
				ctx.js_throw(ctx.js_error(message: err.msg()))
			}
		})
		defer {
			open.free()
		}
		constructor := ctx.call(factory, open)!
		defer {
			constructor.free()
		}
		mut sqlite_mod := ctx.js_module('node:sqlite')
		sqlite_mod.export('DatabaseSync', constructor)
		default_obj := ctx.js_object()
		default_obj.set('DatabaseSync', constructor)
		sqlite_mod.export_default(default_obj)
		sqlite_mod.create()
		default_obj.free()
	}
}
