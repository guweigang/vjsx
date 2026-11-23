import os
import vjsx
import vjsx.runtimejs

fn test_host_module_mirror_base_keeps_emitted_entry_short_and_imports_intact() ! {
	root := os.join_path(os.real_path(os.temp_dir()), 'vjsx-host-mirror-${os.getpid()}')
	source := os.join_path(root, '项目 with spaces', 'deep'.repeat(20))
	output := os.join_path(root, 'out')
	os.mkdir_all(source)!
	defer { os.rmdir_all(root) or {} }
	entry := os.join_path(source, 'main.mjs')
	os.write_file(entry, 'import { answer } from "./dep.mjs"; globalThis.__mirror_answer = answer;')!
	os.write_file(os.join_path(source, 'dep.mjs'), 'export const answer = 42;')!
	mut session := vjsx.new_runtime_session()
	defer { session.close() }
	emitted := runtimejs.build_runtime_module_entry_with_mirror_base(session.context(), entry, true, output, source)!
	assert emitted == os.join_path(output, 'main.mjs')
	assert os.is_file(os.join_path(output, 'dep.mjs'))
	assert !emitted.contains('项目 with spaces')
	value := session.context().run_file(emitted, vjsx.type_module)!
	value.free()
	answer := session.context().eval('globalThis.__mirror_answer')!
	defer { answer.free() }
	assert answer.to_int() == 42
}
