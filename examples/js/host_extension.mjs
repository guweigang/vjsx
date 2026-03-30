export const extension = {
  name: "host-extension",
  capabilities: ["demo"],
};

let lastActivation = "none";

export function activate(host, name) {
  lastActivation = `${host.app.name}:${name}`;
  return `activate:${host.logger.prefix}:${name}`;
}

export function dispose(host) {
  return `dispose:${host.app.name}:${lastActivation}`;
}

export function greet(host, name) {
  return `hello:${host.app.name}:${name}`;
}

export default {
  status(host, value) {
    return `status:${host.app.name}:${value}`;
  },
};
