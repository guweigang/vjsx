import hostTools from "host-tools";

export const extension = {
  name: "host-extension-manifest",
  capabilities: ["demo", "manifest"],
  services: {
    hostGreeting: "hostGreeting",
  },
  hooks: {
    activate: "boot",
    handle: "runTask",
    dispose: "teardown",
  },
};

let activation = "none";

export function boot(host, name) {
  activation = `${host.app.name}:${name}`;
  return `boot:${host.logger.prefix}:${name}:${hostTools.version}`;
}

export function runTask(host, input) {
  return `run:${host.app.name}:${input}:${activation}`;
}

export function hostGreeting(_host, name) {
  return hostTools.greet(name);
}

export function teardown(host) {
  return `teardown:${host.app.name}:${activation}`;
}
