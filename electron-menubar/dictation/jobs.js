// Reserve insertion order at recording START, even if audio delivery or HTTP races.
function createDictationJobs() {
  let sequence = 0;
  let tail = Promise.resolve();
  let current = null;
  const pending = new Map();
  return {
    create(target = null, settings = null) {
      let release;
      const previous = tail;
      tail = new Promise(resolve => { release = resolve; });
      const job = { id: `${Date.now()}-${++sequence}`, target, settings, phase: 'starting',
        turn: previous, finish: () => { pending.delete(job.id); previous.then(release); } };
      pending.set(job.id, job);
      current = job;
      return job;
    },
    get: id => pending.get(id),
    pending: () => [...pending.values()],
    isCurrent: job => current === job,
    get current() { return current; },
  };
}
module.exports = { createDictationJobs };
