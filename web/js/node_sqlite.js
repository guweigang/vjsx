(open) => {
	class StatementSync {
		#execute;
		#sql;
		#readBigInts = false;

		constructor(execute, sql) {
			this.#execute = execute;
			this.#sql = sql;
		}

		setReadBigInts(enabled) {
			if (typeof enabled !== "boolean") throw new TypeError("readBigInts must be a boolean");
			this.#readBigInts = enabled;
		}

		run(...params) {
			return this.#execute("run", this.#sql, this.#readBigInts, ...params);
		}

		get(...params) {
			return this.#execute("get", this.#sql, this.#readBigInts, ...params);
		}

		all(...params) {
			return this.#execute("all", this.#sql, this.#readBigInts, ...params);
		}
	}

	function checkSql(sql) {
		if (typeof sql !== "string" || sql.includes("\0")) {
			throw new TypeError("SQL must be a string without NUL characters");
		}
	}

	return class DatabaseSync {
		#handle;

		constructor(path, { readOnly = false, timeout = 0 } = {}) {
			if (typeof path !== "string" || path.includes("\0")) {
				throw new TypeError("SQLite path must be a string without NUL characters");
			}
			if (typeof readOnly !== "boolean") throw new TypeError("readOnly must be a boolean");
			if (!Number.isInteger(timeout) || timeout < 0 || timeout > 2147483647) {
				throw new RangeError("timeout must be a non-negative 32-bit integer");
			}
			this.#handle = open(path, readOnly, timeout);
		}

		exec(sql) {
			checkSql(sql);
			this.#handle.execute("exec", sql);
		}

		prepare(sql) {
			checkSql(sql);
			const execute = this.#handle.execute;
			execute("prepare", sql);
			return new StatementSync(execute, sql);
		}

		close() {
			this.#handle.close();
		}
	};
}
