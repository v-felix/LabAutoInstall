"use strict";
const fs = require("node:fs"), path = require("node:path"), vm = require("node:vm"), crypto = require("node:crypto");
const root = path.resolve(process.argv[2]);
const context = vm.createContext({URL, module:{exports:{}}});
vm.runInContext(fs.readFileSync(path.join(root,"config.js"),"utf8"),context,{timeout:1000});
vm.runInContext(fs.readFileSync(path.join(root,"core.js"),"utf8"),context,{timeout:1000});
const c = context.SfitCore.validate(context.SFIT_CONFIG);
const m = JSON.parse(fs.readFileSync(path.join(root,"manifest.json"),"utf8"));
if (m.manifest_version !== 3 || !m.key) throw new Error("Need Manifest V3 and a stable public key");
const id = [...crypto.createHash("sha256").update(Buffer.from(m.key,"base64")).digest().subarray(0,16)].map(b=>String.fromCharCode(97+(b>>4),97+(b&15))).join("");
console.log(JSON.stringify({id,version:m.version,configSha256:crypto.createHash("sha256").update(fs.readFileSync(path.join(root,"config.js"))).digest("hex"),
  startAt:c.startAt,endAt:c.endAt,phase:context.SfitCore.phase(c),enabled:c.enabled}));
