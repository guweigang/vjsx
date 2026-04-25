/* Credit: All VJS Author */
import * as os from "qjs:os";

let nextRuntimeTimerWakeupId = 1;
const timeoutWakeupIds = new Map();
const intervalWakeupIds = new Map();

function runtimeTimerWakeup() {
  const hook = globalThis.__vjsxRuntimeTimerWakeup;
  if (hook === undefined || hook === null) {
    return undefined;
  }
  if (typeof hook.schedule !== "function" || typeof hook.cancel !== "function") {
    return undefined;
  }
  return hook;
}

function normalizeDelay(delay) {
  const n = Number(delay);
  if (!Number.isFinite(n) || n < 0) {
    return 0;
  }
  return Math.trunc(n);
}

function scheduleWakeup(id, delay) {
  const hook = runtimeTimerWakeup();
  if (hook !== undefined) {
    hook.schedule(String(id), normalizeDelay(delay));
  }
}

function cancelWakeup(id) {
  const hook = runtimeTimerWakeup();
  if (hook !== undefined) {
    hook.cancel(String(id));
  }
}

globalThis.setTimeout = (cb, delay, ...args) => {
  const wakeupId = nextRuntimeTimerWakeupId++;
  const timer = os.setTimeout(() => {
    timeoutWakeupIds.delete(timer);
    cancelWakeup(wakeupId);
    cb(...args);
  }, normalizeDelay(delay));
  timeoutWakeupIds.set(timer, wakeupId);
  scheduleWakeup(wakeupId, delay);
  return timer;
};

globalThis.clearTimeout = (timer) => {
  const wakeupId = timeoutWakeupIds.get(timer);
  if (wakeupId !== undefined) {
    timeoutWakeupIds.delete(timer);
    cancelWakeup(wakeupId);
  }
  return os.clearTimeout(timer);
};

const timers = new Map();
globalThis.setInterval = (cb, interval, ...args) => {
  const timer = {};
  const state = { enabled: true };
  timers.set(timer, state);
  const fn = () => {
    const wakeupId = nextRuntimeTimerWakeupId++;
    intervalWakeupIds.set(timer, wakeupId);
    scheduleWakeup(wakeupId, interval);
    os.setTimeout(() => {
      intervalWakeupIds.delete(timer);
      cancelWakeup(wakeupId);
      if (!state.enabled) {
        return;
      }
      cb(...args);
      fn();
    }, normalizeDelay(interval));
  };
  fn();
  return timer;
};

globalThis.clearInterval = (timer) => {
  const state = timers.get(timer);
  if (state === undefined) {
    return false;
  }
  state.enabled = false;
  timers.delete(timer);
  const wakeupId = intervalWakeupIds.get(timer);
  if (wakeupId !== undefined) {
    intervalWakeupIds.delete(timer);
    cancelWakeup(wakeupId);
  }
  return true;
};
