export function greet(host, name) {
  return `${host.app.name}:${name}:${host.math.add(2, 3)}`;
}

export const worker = {
  run(host, job) {
    return `${host.logger.prefix}:${job}:${host.math.add(4, 5)}`;
  },
};

export default {
  handle(host, task) {
    return `${host.app.name}:${task}:${host.logger.prefix}`;
  },
};
