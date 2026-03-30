export const meaning = 42;

export function greet(name) {
  return `hello:${name}`;
}

export default {
  label: "default-export",
  format(name) {
    return `default:${name}`;
  },
};
