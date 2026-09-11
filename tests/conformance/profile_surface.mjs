export function profileSurface() {
  return [
    typeof process,
    typeof Buffer,
    typeof fetch,
    typeof setTimeout,
    typeof window,
    typeof self,
  ].join("|");
}
