import os
import tests.cli_test_support

fn test_cli_example_db_sqlite_basic() {
	db_path := os.join_path(@VMODROOT, 'examples', 'db', '.examples_sqlite_basic.db')
	os.rm(db_path) or {}
	output :=
		os.execute('${cli_test_support.command(true)} --module ./examples/db/sqlite_basic.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == '1:alice\n3\nalice,bob|bob,carol'
	assert !os.exists(db_path)
}

fn test_cli_host_sqlite_runtime_features() {
	db_path := os.join_path(@VMODROOT, 'tests', '.host_sqlite_runtime.db')
	os.rm(db_path) or {}
	output :=
		os.execute('${cli_test_support.command(true)} --module ./tests/host_sqlite_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'false\ntrue\nfalse\ntrue\n1\n0\n1\n1\n1\n1\n2\n1:alice\n1:alice\ntrue\n2\ntrue\nalice|bob\n2\n3\n4'
	assert !os.exists(db_path)
}

fn test_cli_host_sqlite_transaction_helper() {
	db_path := os.join_path(@VMODROOT, 'tests', '.host_sqlite_transaction_runtime.db')
	os.rm(db_path) or {}
	output :=
		os.execute('${cli_test_support.command(true)} --module ./tests/host_sqlite_transaction_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'false\ntrue\nfalse\n2\nrollback-me\nalice,bob'
	assert !os.exists(db_path)
}

fn test_cli_host_sqlite_statement_helper() {
	db_path := os.join_path(@VMODROOT, 'tests', '.host_sqlite_statement_runtime.db')
	os.rm(db_path) or {}
	output :=
		os.execute('${cli_test_support.command(true)} --module ./tests/host_sqlite_statement_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'sqlite\ntrue\nsqlite\ntrue\nsqlite.Connection{path: /Users/guweigang/Source/vjsx/tests/.host_sqlite_statement_runtime.db, closed: false, inTransaction: false}\nsqlite.Statement{kind: exec, closed: false, sql: insert into users(name) values (?)}\ntrue\ninsert into users(name) values (?)\nexec\nquery\nfalse\n1\n1\n2\n2\n3\n1:alice,2:bob\n1:alice\ntrue\n3\nnull\nalice,bob|bob,carol\ntrue\ntrue\nfalse\ntrue'
	assert !os.exists(db_path)
}

fn test_cli_host_sqlite_close_lifecycle() {
	db_path := os.join_path(@VMODROOT, 'tests', '.host_sqlite_close_runtime.db')
	os.rm(db_path) or {}
	output :=
		os.execute('${cli_test_support.command(true)} --module ./tests/host_sqlite_close_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'true\ntrue\ntrue\ntrue\ntrue\nfalse\ntrue\ntrue\nError:sqlite connection is closed'
	assert !os.exists(db_path)
}

fn test_cli_host_mysql_module_available() {
	output :=
		os.execute('${cli_test_support.command(false)} --module ./tests/host_mysql_module_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'function'
}

fn test_cli_host_error_runtime_features() {
	db_path := os.join_path(@VMODROOT, 'tests', '.host_error_runtime.db')
	os.rm(db_path) or {}
	output :=
		os.execute('${cli_test_support.command(true)} --module ./tests/host_error_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'TypeError:options.path must be a string\nTypeError:options.busyTimeout must be a number\nTypeError:params must be an array\nTypeError:each param batch must be an array\nTypeError:params must be an array\nError:sqlite statement is closed\nError:sqlite connection is closed\nTypeError:options object is required\nTypeError:options.port must be a number\nError:mysql support is not built in; rerun with -d vjsx_mysql'
	assert !os.exists(db_path)
}
