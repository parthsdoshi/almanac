/**
 * APNs push-to-start payload. "attributes" and "content-state" must match the
 * Swift OccasionAttributes struct exactly (Shared/OccasionAttributes.swift).
 */

/** Mirrors Names.join in Shared/OccasionKind.swift. */
export function joinNames(names) {
  if (names.length <= 1) return names[0] ?? '';
  if (names.length === 2) return `${names[0]} & ${names[1]}`;
  return `${names.slice(0, -1).join(', ')} & ${names.at(-1)}`;
}

export function headline(kind, names) {
  const who = joinNames(names);
  return kind === 'anniversary' ? `${who}'s anniversary` : `${who}'s birthday`;
}

export function pushToStartPayload(occasion, { now = new Date() } = {}) {
  const title = headline(occasion.kind, occasion.names);
  const body = occasion.kind === 'anniversary'
    ? 'Send them a note or give them a call.'
    : `Wish ${occasion.names[0]} a happy birthday.`;
  return {
    aps: {
      timestamp: Math.floor(now.getTime() / 1000),
      event: 'start',
      'attributes-type': 'OccasionAttributes',
      attributes: {
        occasionID: occasion.id,
        kind: occasion.kind,
        names: occasion.names,
      },
      'content-state': { headline: title },
      alert: { title, body },
    },
  };
}
