module runtimejs

// SessionLaneLoad is the I/O-free input to lane admission policy.
pub struct SessionLaneLoad {
pub:
	queued   int
	running  bool
	draining bool
}

pub enum SessionLaneAdmission {
	admit
	refuse_full
	refuse_draining
}

// decide_session_lane_admission contains no clocks, locks or I/O so hosts can
// test admission decisions independently from thread scheduling.
pub fn decide_session_lane_admission(load SessionLaneLoad, config SessionLaneConfig) SessionLaneAdmission {
	if load.draining {
		return .refuse_draining
	}
	if config.max_queue > 0 && load.queued >= config.max_queue {
		return .refuse_full
	}
	return .admit
}

pub fn session_lane_admission_timed_out(waited_ms u64, admission_wait_ms u64) bool {
	return admission_wait_ms == 0 || waited_ms >= admission_wait_ms
}
