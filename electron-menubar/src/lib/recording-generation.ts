/** Invalidates pending settings/getUserMedia continuations, including unmounts. */
export function createRecordingGeneration() {
  let generation = 0;
  return {
    begin: () => ++generation,
    cancel: () => { generation++; },
    isCurrent: (token: number) => token === generation,
    acceptStream(token: number, stream: MediaStream) {
      if (token === generation) return true;
      stream.getTracks().forEach(track => track.stop());
      return false;
    },
  };
}
