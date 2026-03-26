async function resolveValue(input, url, options) {
	return 1;
}

const value = await resolveValue({}, 'https://example.com/article', { markdown: true });
console.log(String(value));
