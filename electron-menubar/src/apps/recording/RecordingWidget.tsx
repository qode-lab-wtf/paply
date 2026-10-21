import { RecordingPill } from './RecordingPill';
import { useDictationRecorder } from './useDictationRecorder';

export function RecordingWidget() {
  return <RecordingPill {...useDictationRecorder()} />;
}
