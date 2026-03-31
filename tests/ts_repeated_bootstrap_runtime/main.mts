import { answer } from "./value.ts";

const api = {
	format(prefix: string) {
		return `${prefix}:${answer}`;
	},
};

globalThis.__vjsx_repeated_bootstrap_value = api.format("ok");
