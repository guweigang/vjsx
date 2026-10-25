import vjsx
import os

fn test_fs_descriptors_are_durable_context_scoped_and_policy_checked() {
	root := os.join_path(os.temp_dir(), 'vjsx-fd-${os.getpid()}')
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	mut policy := vjsx.host_policy_trusted()
	policy.fs_read_roots = [root]
	policy.fs_write_roots = [root]
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{ policy: policy })
	defer { session.close() }
	ctx := session.context()
	global := ctx.js_global()
	global.set('testRoot', root)
	global.free()
	result := ctx.js_eval('
 import fs from "node:fs";
 import { pathToFileURL, fileURLToPath } from "node:url";
 const pending = testRoot + "/state.pending";
 const target = testRoot + "/state.json";
 const fd = fs.openSync(pending,"wx",0o600);
 if(fs.writeSync(fd,"员工反馈") !== new TextEncoder().encode("员工反馈").length) throw Error("partial write");
 fs.fsyncSync(fd);fs.closeSync(fd);fs.renameSync(pending,target);
 if(process.platform !== "win32") { const dir=fs.openSync(testRoot,"r");fs.fsyncSync(dir);fs.closeSync(dir); }
 if(fs.readFileSync(target,"utf8") !== "员工反馈")throw Error("durable write mismatch");
 for(const fn of [()=>fs.writeSync(1,"no"),()=>fs.fsyncSync(fd),()=>fs.closeSync(fd),()=>fs.openSync("/outside-policy","w"),()=>fs.renameSync(target,"/outside-policy")]) {
  let denied=false;try{fn();}catch{denied=true;}if(!denied)throw Error("descriptor or policy bypass");
 }
 const special=testRoot+"/员工 #1?.txt";
 if(fileURLToPath(pathToFileURL(special)).replaceAll(String.fromCharCode(92),"/")!==special.replaceAll(String.fromCharCode(92),"/"))throw Error("file URL round trip");
 // Leave a descriptor open: Context cleanup must close it.
 fs.openSync(target,"r");
 globalThis.fsDescriptorPassed=true;
 ', 'fs-descriptors.mjs', vjsx.type_module) or { panic(err) }
	result.free()
	passed := ctx.js_global('fsDescriptorPassed')
	defer { passed.free() }
	assert passed.to_bool()
}
