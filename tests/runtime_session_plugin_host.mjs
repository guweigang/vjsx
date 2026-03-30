let last_app = "none";

export function activate(host, name) {
  last_app = host.app.name;
  return `${host.logger.prefix}:${name}:${host.math.add(2, 5)}`;
}

export function handle(host, input) {
  return `${host.app.name}:${input}:${last_app}`;
}

export function dispose(host) {
  return `dispose:${host.app.name}:${last_app}`;
}
