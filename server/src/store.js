import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';

/**
 * The whole state is one small JSON file on the Render disk:
 *   { devices: { [deviceId]: Device } }
 * One user, a few hundred occasions at most, so a database would be overkill.
 * Writes are serialized and atomic (temp file + rename).
 */
export class JsonStore {
  constructor(file) {
    this.file = file;
    this.data = { devices: {} };
    this.queue = Promise.resolve();
  }

  async load() {
    try {
      this.data = JSON.parse(await readFile(this.file, 'utf8'));
    } catch (err) {
      if (err.code !== 'ENOENT') throw err;
    }
    this.data.devices ??= {};
    return this;
  }

  device(id) {
    return this.data.devices[id];
  }

  devices() {
    return Object.entries(this.data.devices);
  }

  /** Applies `fn` to the data and persists it. Calls run one at a time. */
  mutate(fn) {
    const run = async () => {
      fn(this.data);
      await this.#persist();
    };
    const result = this.queue.then(run, run);
    this.queue = result.catch(() => {});
    return result;
  }

  async #persist() {
    await mkdir(dirname(this.file), { recursive: true });
    const tmp = `${this.file}.tmp`;
    await writeFile(tmp, JSON.stringify(this.data));
    await rename(tmp, this.file);
  }
}
