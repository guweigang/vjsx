module vjsx

fn artifact_runtime_abi_compatible(value string) bool {
	if value == artifact_abi {
		return true
	}
	// Format-1 artifacts produced before ABI v1 stored the vjsx product version
	// in this field. All historical 0.0.x artifacts map to ABI v1; QuickJS ABI
	// and runtime-profile checks still apply. Other legacy lines are rejected.
	parts := value.split('.')
	return parts.len == 3 && parts[0] == '0' && parts[1] == '0'
}
