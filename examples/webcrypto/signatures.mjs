const text = new TextEncoder().encode("hello");

const ed = await crypto.subtle.generateKey("Ed25519", false, ["sign", "verify"]);
const edSignature = await crypto.subtle.sign("Ed25519", ed.privateKey, text);
const edVerified = await crypto.subtle.verify("Ed25519", ed.publicKey, edSignature, text);

const ec = await crypto.subtle.generateKey(
  { name: "ECDSA", namedCurve: "P-256" },
  false,
  ["sign", "verify"],
);
const ecSignature = await crypto.subtle.sign(
  { name: "ECDSA", hash: "SHA-256" },
  ec.privateKey,
  text,
);
const ecVerified = await crypto.subtle.verify(
  { name: "ECDSA", hash: "SHA-256" },
  ec.publicKey,
  ecSignature,
  text,
);

console.log(`Ed25519:${edSignature.byteLength}:${edVerified}`);
console.log(`ECDSA:${ecSignature.byteLength}:${ecVerified}`);
