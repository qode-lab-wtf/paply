class NotesPCM extends AudioWorkletProcessor {
  constructor() {
    super(); this.samples = new Int16Array(8000); this.length = 0; this.peak = 0; this.finished = false;
    this.ratio = sampleRate / 16000; this.weight = 0; this.sum = 0;
    this.port.onmessage = e => { if (e.data === 'flush') { this.emit(); this.finished = true; this.port.postMessage({ type: 'flushed' }); } };
  }
  emit() {
    if (!this.length) return;
    const bytes = this.samples.slice(0, this.length).buffer;
    this.port.postMessage({ type: 'pcm', bytes, level: this.peak }, [bytes]); this.length = 0; this.peak = 0;
  }
  process(inputs) {
    if (this.finished) return false;
    const input = inputs[0]?.[0]; if (!input) return true;
    for (let i = 0; i < input.length; i++) {
      let remaining = 1;
      while (remaining > 1e-8) {
        const weight = Math.min(remaining, this.ratio - this.weight);
        this.sum += input[i] * weight; this.weight += weight; remaining -= weight;
        if (this.weight >= this.ratio - 1e-8) {
          const sample = Math.max(-1, Math.min(1, this.sum / this.ratio)); this.peak = Math.max(this.peak, Math.abs(sample));
          this.samples[this.length++] = sample < 0 ? sample * 32768 : sample * 32767;
          this.sum = 0; this.weight = 0;
          if (this.length === this.samples.length) this.emit();
        }
      }
    }
    return true;
  }
}
registerProcessor('paply-notes-pcm', NotesPCM);
