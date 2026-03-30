let last_app = "none";

export function activate(host, name) {
  last_app = host.app.name;
  return `activate:${host.logger.prefix}:${name}`;
}

export function handle(host, input) {
  return `handle:${host.app.name}:${input}:${last_app}`;
}

export function dispose(host) {
  return `dispose:${host.app.name}:${last_app}`;
}

export function greet(host, name) {
  return `greet:${host.app.name}:${name}`;
}

export const service = {
  run(host, task) {
    return `service:${host.logger.prefix}:${task}`;
  },
};

export default {
  status(host, value) {
    return `status:${host.app.name}:${value}`;
  },
};
