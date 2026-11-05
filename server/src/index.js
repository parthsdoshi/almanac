import { ApnsClient } from './apns.js';
import { loadConfig } from './config.js';
import { tick } from './scheduler.js';
import { createServer } from './server.js';
import { JsonStore } from './store.js';

const config = loadConfig();
const store = await new JsonStore(config.dataFile).load();
const apns = config.apns ? new ApnsClient(config.apns) : null;
if (!apns) console.warn(`APNs not configured (missing ${config.apnsMissing.join(', ')}); nothing will be sent.`);

const server = createServer({ store, apiKey: config.apiKey, apns });
server.listen(config.port, () => console.info(`listening on ${config.port}`));

let running = false;
async function runTick() {
  if (running) return;
  running = true;
  try {
    await tick({ store, apns });
  } catch (err) {
    console.error('tick failed', err);
  } finally {
    running = false;
  }
}
await runTick();
const timer = setInterval(runTick, config.tickMs);

process.on('SIGTERM', () => {
  clearInterval(timer);
  server.close(() => {
    apns?.close();
    process.exit(0);
  });
});
