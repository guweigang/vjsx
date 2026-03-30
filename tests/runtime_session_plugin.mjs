let activation_count = 0;

export function activate(name) {
  activation_count += 1;
  return `activate:${name}:${activation_count}`;
}

export function handle(input) {
  return `handle:${input}:${activation_count}`;
}

export function dispose() {
  const result = `dispose:${activation_count}`;
  activation_count = 0;
  return result;
}
