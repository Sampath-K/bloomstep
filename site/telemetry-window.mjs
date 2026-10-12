const dayMs = 24 * 60 * 60 * 1000;

/** Choose a simulated start whose whole acceptance span stays inside the current UTC day.
 * The one-day persisted readback suppresses split-day counts below 50, so crossing midnight is invalid.
 * @param {number} realNow @param {number} spanMs */
export function telemetryWindowStart(realNow, spanMs) {
  if (!(spanMs > 0 && spanMs < dayMs - 60000)) throw RangeError('Telemetry window must fit inside one UTC day.');
  const dayStart = realNow - (realNow % dayMs);
  return realNow + spanMs < dayStart + dayMs ? realNow : dayStart + 60000;
}
