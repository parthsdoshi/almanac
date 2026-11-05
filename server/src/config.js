import { existsSync, readFileSync } from 'node:fs';

const DEFAULT_KEY_PATH = '/etc/secrets/AuthKey.p8'; // Render secret file

export function loadConfig(env = process.env) {
  const apiKey = env.API_KEY?.trim();
  if (!apiKey || apiKey.length < 16) {
    throw new Error('API_KEY must be set (16+ characters).');
  }

  let privateKey = env.APNS_PRIVATE_KEY?.replace(/\\n/g, '\n').trim();
  const keyPath = env.APNS_PRIVATE_KEY_PATH || DEFAULT_KEY_PATH;
  if (!privateKey && existsSync(keyPath)) privateKey = readFileSync(keyPath, 'utf8').trim();

  const apns = {
    keyId: env.APNS_KEY_ID?.trim(),
    teamId: env.APNS_TEAM_ID?.trim(),
    bundleId: env.APNS_BUNDLE_ID?.trim(),
    privateKey,
  };
  const missing = Object.entries(apns).filter(([, v]) => !v).map(([k]) => k);

  return {
    apiKey,
    apns: missing.length ? null : apns,
    apnsMissing: missing,
    dataFile: `${env.DATA_DIR || './data'}/state.json`,
    port: Number(env.PORT || 3000),
    tickMs: Number(env.TICK_MS || 5 * 60 * 1000),
  };
}
