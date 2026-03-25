import { graphWord } from "./words.ts";

export function readMessage(): string {
  return graphWord() + " ready";
}
