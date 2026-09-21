// Carries fractional input samples across AudioWorklet blocks; never rounds each block.
export class MeetingResampler {
  private filled = 0;
  private sum = 0;
  private readonly width: number;
  constructor(fromRate: number, toRate = 16000) {
    if (!(fromRate > 0 && toRate > 0)) throw new Error('Invalid audio rate');
    this.width = fromRate / toRate;
  }
  push(input: Float32Array): Float32Array {
    const output: number[] = [];
    for (const sample of input) {
      let remaining = 1;
      while (remaining > 1e-10) {
        const amount = Math.min(remaining, this.width - this.filled);
        this.sum += sample * amount;
        this.filled += amount;
        remaining -= amount;
        if (this.filled >= this.width - 1e-10) {
          output.push(this.sum / this.width);
          this.sum = 0; this.filled = 0;
        }
      }
    }
    return Float32Array.from(output);
  }
  flush(): Float32Array {
    const result = this.filled > 1e-10 ? Float32Array.of(this.sum / this.filled) : new Float32Array(0);
    this.sum = 0; this.filled = 0;
    return result;
  }
}
