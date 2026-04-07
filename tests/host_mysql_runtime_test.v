import os

fn test_cli_host_mysql_runtime_features() {
	if os.getenv('VJS_TEST_MYSQL_HOST') == '' && os.getenv('VJS_TEST_MYSQL_DBNAME') == '' {
		return
	}
	output := os.execute('VJS_V_FLAGS="-d vjsx_mysql" sh ./vjsx --module ./tests/host_mysql_runtime.mjs')
	assert output.exit_code == 0
	assert output.output.trim_space() == 'mysql\ntrue\nmysql.Connection{closed: false, inTransaction: false}\nfalse\ntrue\nfalse\nmysql\ntrue\nmysql.Statement{kind: exec, closed: false, sql: insert into vjsx_host_mysql_runtime(name) values (?)}\ntrue\nexec\nquery\ntrue\n1\n0\n1\n1\n2\n2\n2:alice\n2:alice\ntrue\n1\ntrue\nalice|\n2\n3\n4\n5\n2\n6\n7\n3:bob,4:zoe,5:carol,6:dave,7:erin\n3:bob\n6\nalice,bob,zoe,carol,dave|alice,bob,zoe,dave,erin\ntrue\ntrue\nfalse\ntrue\ntrue\nError:mysql connection is closed'
}
