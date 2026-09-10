module vjsx

fn test_artifact_abi_is_independent_from_product_patch_version() {
	assert artifact_runtime_abi_compatible(artifact_abi)
	assert artifact_runtime_abi_compatible('0.0.1')
	assert artifact_runtime_abi_compatible('0.0.99')
	assert !artifact_runtime_abi_compatible('0.1.0')
	assert !artifact_runtime_abi_compatible('vjsx-artifact-abi/2')
}

fn test_bundle_abi_validation_ignores_product_patch_and_migrates_legacy_v0() {
	mut session := new_runtime_session()
	defer { session.close() }
	ctx := session.context()
	ctx.set_runtime_profile('node')
	ctx.validate_bundle_manifest(BundleManifest{
		format_version: 1
		vjsx_version: '0.0.999'
		runtime_abi: artifact_abi
		quickjs_abi: quickjs_abi_fingerprint()
		runtime_profile: 'node'
	}) or { panic(err) }
	ctx.validate_bundle_manifest(BundleManifest{
		format_version: 1
		vjsx_version: '0.0.1'
		quickjs_abi: quickjs_abi_fingerprint()
		runtime_profile: 'node'
	}) or { panic(err) }
	ctx.validate_bundle_manifest(BundleManifest{
		format_version: 1
		vjsx_version: version
		runtime_abi: 'vjsx-artifact-abi/2'
		quickjs_abi: quickjs_abi_fingerprint()
		runtime_profile: 'node'
	}) or {
		assert err.msg().contains('incompatible vjsx artifact ABI')
		return
	}
	assert false
}
