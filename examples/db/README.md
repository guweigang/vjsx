# Database Host Examples

These examples target the default Node-style host profile exposed by `vjsx`.

SQLite:

```bash
./vjsx --module ./examples/db/sqlite_basic.mjs
```

MySQL:

```bash
VJS_V_FLAGS='-d vjsx_mysql' ./vjsx --module ./examples/db/mysql_basic.mjs
```

For the MySQL example, configure the same environment variables used by the
runtime test when needed:

- `VJS_TEST_MYSQL_HOST`
- `VJS_TEST_MYSQL_PORT`
- `VJS_TEST_MYSQL_USER`
- `VJS_TEST_MYSQL_PASSWORD`
- `VJS_TEST_MYSQL_DBNAME`
- `VJS_TEST_MYSQL_TABLE`
