/** Pure date logic. Mirrors App/Models/Recurrence.swift. */

const pad = (n) => String(n).padStart(2, '0');

/** Wall-clock parts of `date` in `timeZone`. Throws RangeError for unknown zones. */
export function localParts(date, timeZone) {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
    hourCycle: 'h23',
  });
  const p = Object.fromEntries(fmt.formatToParts(date).map(({ type, value }) => [type, Number(value)]));
  return { year: p.year, month: p.month, day: p.day, hour: p.hour, minute: p.minute, second: p.second };
}

export function isValidTimeZone(timeZone) {
  try {
    localParts(new Date(), timeZone);
    return true;
  } catch {
    return false;
  }
}

/** The day an occasion is observed in `year`: Feb 29 falls back to Feb 28, bad days clamp. */
export function observedDay(month, day, year) {
  const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
  return Math.min(day, lastDay);
}

/** Don't start "today" Live Activities this late in the evening, even after an outage. */
export const LAST_SEND_HOUR = 21;

/**
 * What to send for one device at `now`: today's occasions once the device's
 * local send hour has passed, minus any already sent today.
 */
export function dueOccasions(device, now) {
  const p = localParts(now, device.timeZone);
  const localDate = `${p.year}-${pad(p.month)}-${pad(p.day)}`;
  if (p.hour < device.sendHour || p.hour >= Math.max(LAST_SEND_HOUR, device.sendHour + 1)) {
    return { localDate, due: [] };
  }
  const sent = device.sent ?? {};
  const due = device.occasions.filter(
    (o) => o.month === p.month && observedDay(o.month, o.day, p.year) === p.day && sent[o.id] !== localDate,
  );
  return { localDate, due };
}

/** Unix seconds at the end of the device's local day (used as the push expiration). */
export function endOfLocalDay(now, timeZone) {
  const p = localParts(now, timeZone);
  const secondsLeft = (23 - p.hour) * 3600 + (59 - p.minute) * 60 + (60 - p.second);
  return Math.floor(now.getTime() / 1000) + secondsLeft;
}
