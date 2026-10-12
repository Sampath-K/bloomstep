export const resumeConfirmation = 'reviewed-free-tier-and-spending-limit';
const uuid = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;
const reasons = ['paid_sku', 'spending_limit_off', 'positive_cost', 'configuration_unknown'];

export function parsePauseStatus(value) {
  const keys = value && typeof value === 'object' ? Object.keys(value).sort().join(',') : '';
  if (value?.paused === false && keys === 'paused') return { paused: false };
  if (value?.paused === true && keys === 'paused,pausedAt,reason,requestId' && uuid.test(value.requestId) &&
      reasons.includes(value.reason) && typeof value.pausedAt === 'string') {
    return { paused: true, requestId: value.requestId, reason: value.reason, pausedAt: value.pausedAt };
  }
  throw Error('Invalid pause status response.');
}

export function pauseSummary(status) {
  if (!status.paused) return 'Remote writes and team engagement are not paused.';
  return `Paused for spending review. Pause ID: ${status.requestId}. Reason: ${status.reason}. Paused at: ${status.pausedAt}. ` +
    'Confirm the Azure subscription is still Free Trial with the spending limit on and only Free SKUs exist, then type this pause ID to resume.';
}

export function resumePayload(status, typedPauseId, id = () => crypto.randomUUID()) {
  if (!status) throw Error('Load the current pause status first.');
  if (!status.paused) throw Error('Operations are not paused; nothing to resume.');
  if (String(typedPauseId ?? '').trim().toLowerCase() !== status.requestId.toLowerCase()) {
    throw Error('Type the current pause ID exactly to confirm your spending review.');
  }
  return { requestId: id(), reviewedPauseRequestId: status.requestId, confirmation: resumeConfirmation };
}
