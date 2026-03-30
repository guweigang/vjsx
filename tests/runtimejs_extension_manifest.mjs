let activation = "none";

export const extension = {
  name: "manifest-extension",
  capabilities: ["search", "index"],
  services: {
    greet: "greet",
    taskRunner: { export: "service", method: "run" },
    status: { export: "default", method: "status" },
  },
  hooks: {
    activate: "boot",
    handle: "run",
    dispose: "teardown",
  },
};

export function boot(host, name) {
  activation = `${host.app.name}:${name}`;
  return `boot:${activation}`;
}

export function run(host, input) {
  return `run:${host.logger.prefix}:${input}:${activation}`;
}

export function teardown(host) {
  return `teardown:${host.app.name}:${activation}`;
}

export function greet(host, name) {
  return `hello:${host.app.name}:${name}`;
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
