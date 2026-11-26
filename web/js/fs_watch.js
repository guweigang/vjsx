import * as os from "qjs:os";

globalThis.__vjsxCreateFsWatch = (resolvePath, snapshot) => {
	const active = new Set();
	const pollInterval = 100;
	const enqueue = globalThis.queueMicrotask ?? ((fn) => Promise.resolve().then(fn));

	class FSWatcher {
		#events = new Map();
		#closed = false;
		#referenced;
		#signal;
		#abort = () => this.close();
		#cancel;
		#scan;
		#previous;
		#encode;

		constructor(scan, initial, options, listener) {
			this.#scan = scan;
			this.#previous = initial;
			this.#referenced = options.persistent ?? true;
			this.#signal = options.signal;
			this.#encode = options.encoding === "buffer"
				? (name) => name === null ? null : Buffer.from(name)
				: (name) => name;
			if (listener) this.on("change", listener);
			active.add(this);
			try {
				if (this.#signal?.aborted) {
					enqueue(this.#abort);
				} else {
					this.#schedule();
					this.#signal?.addEventListener("abort", this.#abort, { once: true });
				}
			} catch (error) {
				this.#dispose();
				throw error;
			}
		}

		#schedule() {
			if (this.#closed) return;
			const poll = () => {
				this.#cancel = undefined;
				this.#poll();
			};
			if (typeof setTimeout === "function" &&
				(this.#referenced || globalThis.__vjsxRuntimeTimerWakeup?.runtimeOwned === true)) {
				const timer = setTimeout(poll, pollInterval);
				this.#cancel = () => clearTimeout(timer);
			} else {
				const schedule = this.#referenced ? os.setTimeout : os.setTimeoutUnref;
				if (!schedule) throw Object.assign(new Error("unreferenced timers are unavailable"), { code: "ENOSYS" });
				const timer = schedule(poll, pollInterval);
				this.#cancel = () => os.clearTimeout(timer);
			}
		}

		#poll() {
			let next;
			try {
				next = this.#scan();
			} catch (error) {
				this.close();
				if (!this.emit("error", error)) throw error;
				return;
			}
			const previous = this.#previous;
			this.#previous = next;
			try {
				if (!next || next.root[0] !== previous.root[0]) {
					this.close();
					this.emit("change", "rename", this.#encode(previous.filename));
					return;
				}
				if (next.filename !== null) {
					if (next.root[1] !== previous.root[1]) this.emit("change", "change", this.#encode(next.filename));
					return;
				}
				const before = new Map(previous.entries.map((entry) => [entry[2], entry]));
				for (const [identity, revision, name] of next.entries) {
					if (this.#closed) return;
					const old = before.get(name);
					before.delete(name);
					if (!old || old[0] !== identity) this.emit("change", "rename", this.#encode(name));
					else if (old[1] !== revision) this.emit("change", "change", this.#encode(name));
				}
				for (const name of before.keys()) {
					if (this.#closed) return;
					this.emit("change", "rename", this.#encode(name));
				}
			} finally {
				if (!this.#cancel) this.#schedule();
			}
		}

		#dispose() {
			this.#closed = true;
			active.delete(this);
			this.#cancel?.();
			this.#cancel = undefined;
			this.#previous = undefined;
			this.#signal?.removeEventListener("abort", this.#abort);
		}

		close() {
			if (this.#closed) return;
			this.#dispose();
			enqueue(() => this.emit("close"));
		}

		ref() { return this.#setReferenced(true); }
		unref() { return this.#setReferenced(false); }
		#setReferenced(referenced) {
			if (!this.#closed && this.#referenced !== referenced) {
				this.#referenced = referenced;
				this.#cancel?.();
				this.#cancel = undefined;
				try {
					this.#schedule();
				} catch (error) {
					this.close();
					throw error;
				}
			}
			return this;
		}

		on(name, listener) {
			if (typeof listener !== "function") throw new TypeError("listener must be a function");
			const listeners = this.#events.get(name) ?? [];
			listeners.push(listener);
			this.#events.set(name, listeners);
			return this;
		}
		addListener(name, listener) { return this.on(name, listener); }
		once(name, listener) {
			if (typeof listener !== "function") throw new TypeError("listener must be a function");
			const wrapper = (...args) => {
				this.off(name, wrapper);
				listener.apply(this, args);
			};
			wrapper.listener = listener;
			return this.on(name, wrapper);
		}
		off(name, listener) {
			const listeners = this.#events.get(name);
			const index = listeners?.findLastIndex((entry) => entry === listener || entry.listener === listener) ?? -1;
			if (index >= 0) listeners.splice(index, 1);
			return this;
		}
		removeListener(name, listener) { return this.off(name, listener); }
		emit(name, ...args) {
			const listeners = this.#events.get(name)?.slice() ?? [];
			for (const listener of listeners) listener.apply(this, args);
			return listeners.length !== 0;
		}

		static cleanup() {
			for (const watcher of active) watcher.#dispose();
		}
	}

	function watch(path, options, listener) {
		if (typeof path !== "string" || path.includes("\0") || path === "") {
			throw new TypeError("watch path must be a non-empty string without NUL characters");
		}
		if (typeof options === "function") {
			listener = options;
			options = undefined;
		}
		if (typeof options === "string") options = { encoding: options };
		options ??= {};
		if (typeof options !== "object" || Array.isArray(options)) throw new TypeError("invalid watch options");
		if (listener !== undefined && typeof listener !== "function") throw new TypeError("listener must be a function");
		const { encoding, persistent, recursive, signal } = options;
		for (const value of [persistent, recursive]) {
			if (value !== undefined && typeof value !== "boolean") throw new TypeError("persistent and recursive must be booleans");
		}
		if (encoding !== undefined && !["utf8", "utf-8", "buffer"].includes(encoding)) {
			throw new TypeError("unsupported watch encoding");
		}
		if (signal !== undefined && !(signal instanceof AbortSignal)) throw new TypeError("signal must be an AbortSignal");
		const target = resolvePath(path);
		const scan = () => snapshot(target, recursive ?? false);
		const initial = scan();
		if (!initial) throw Object.assign(new Error("watch path not found: " + path), { code: "ENOENT" });
		return new FSWatcher(scan, initial, { encoding, persistent, signal }, listener);
	}

	return { watch, cleanup: FSWatcher.cleanup };
};
