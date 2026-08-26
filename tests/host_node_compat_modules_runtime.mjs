import fsPromises, { readFile, rm, writeFile } from "node:fs/promises";
import * as barePromises from "fs/promises";
import nodeFs from "node:fs";
import crypto, {
  KeyObject,
  createPrivateKey,
  createPublicKey,
  generateKeyPair,
  generateKeyPairSync,
  sign,
  verify,
} from "node:crypto";
import * as bareCrypto from "crypto";

const file = ".host_node_compat_modules.txt";
await writeFile(file, "promise fs");
console.log(await readFile(file));
console.log(typeof fsPromises.stat + ":" + typeof barePromises.readdir + ":" + typeof nodeFs.readFileSync);
await rm(file);

const privatePem = `-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f
-----END PRIVATE KEY-----`;
const expectedPublicPem = `-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAA6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=
-----END PUBLIC KEY-----
`;
const expectedSignature = "82cb8181627b368dc8d83ae028330ef3dae6478a208095b52e68c4cf31512a9e6e31c1ab44dfaf2b7c5bf11e0520d2422d8ab94e66e4de5ee7a415b579d6720d";
const message = new TextEncoder().encode("vjsx-ed25519");
const privateKey = createPrivateKey(privatePem);
const publicKey = createPublicKey(privateKey);
const signature = sign(null, message, privateKey);

console.log(privateKey instanceof KeyObject);
console.log(privateKey.type + ":" + publicKey.type + ":" + publicKey.asymmetricKeyType);
console.log(publicKey.export({ format: "pem", type: "spki" }) === expectedPublicPem);
console.log(createPublicKey(privatePem).equals(publicKey));
console.log(signature.toString("hex") === expectedSignature);
console.log(verify(null, message, publicKey, signature));
console.log(!verify(null, new TextEncoder().encode("wrong"), publicKey, signature));
console.log(createPrivateKey(privateKey).equals(privateKey));
console.log(crypto.sign === sign);
console.log(bareCrypto.verify === verify);

const generated = generateKeyPairSync("ed25519");
const generatedSignature = sign(null, message, generated.privateKey);
console.log(verify(null, message, generated.publicKey, generatedSignature));
console.log(generated.privateKey.export({ format: "der", type: "pkcs8" }).length === 48);
console.log(generated.publicKey.export({ format: "der", type: "spki" }).length === 44);

const asyncGenerated = await new Promise((resolve, reject) => {
  generateKeyPair("ed25519", (error, asyncPublicKey, asyncPrivateKey) => {
    if (error) return reject(error);
    resolve({ publicKey: asyncPublicKey, privateKey: asyncPrivateKey });
  });
});
console.log(verify(null, message, asyncGenerated.publicKey, sign(null, message, asyncGenerated.privateKey)));

let rejectedMalformedKey = false;
try {
  createPrivateKey({ key: new Uint8Array([0x30, 0x01, 0]), format: "der", type: "pkcs8" });
} catch {
  rejectedMalformedKey = true;
}
console.log(rejectedMalformedKey);
