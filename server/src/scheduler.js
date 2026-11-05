import { sendWithFallback } from './apns.js';
import { pushToStartPayload } from './payload.js';
import { dueOccasions, endOfLocalDay } from './schedule.js';

/**
 * One pass over every device. Runs every few minutes, so a failed send or a
 * restart just retries on the next pass; `sent` makes it idempotent per day.
 * Logs never include names, only occasion ids.
 */
export async function tick({ store, apns, now = new Date(), log = console }) {
  if (!apns) return;
  for (const [deviceId, device] of store.devices()) {
    if (!device.pushToStartToken || device.tokenInvalid) continue;

    let plan;
    try {
      plan = dueOccasions(device, now);
    } catch (err) {
      log.error(`device ${deviceId}: ${err.message}`);
      continue;
    }

    for (const occasion of plan.due) {
      let res;
      try {
        res = await sendWithFallback(apns, {
          deviceToken: device.pushToStartToken,
          env: device.apnsEnvironment,
          payload: pushToStartPayload(occasion, { now }),
          expiration: endOfLocalDay(now, device.timeZone),
        });
      } catch (err) {
        log.error(`device ${deviceId} occasion ${occasion.id}: network error ${err.message}`);
        continue;
      }

      if (res.status === 200) {
        await store.mutate((d) => {
          const current = d.devices[deviceId];
          if (!current) return;
          current.sent = { ...current.sent, [occasion.id]: plan.localDate };
          current.apnsEnvironment = res.env;
        });
        log.info(`device ${deviceId} occasion ${occasion.id}: started`);
      } else if (res.status === 410) {
        // Token is dead. The app sends a fresh one next time it runs.
        await store.mutate((d) => {
          if (d.devices[deviceId]) d.devices[deviceId].tokenInvalid = true;
        });
        log.warn(`device ${deviceId}: token unregistered, waiting for a new one`);
        break;
      } else {
        log.error(`device ${deviceId} occasion ${occasion.id}: APNs ${res.status} ${res.reason ?? ''}`);
      }
    }
  }
}
