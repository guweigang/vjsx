const api = {
	format(name: string) {
		return `plain:${name}`;
	},
};

console.log(api.format("ok"));
