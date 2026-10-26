import type { Note } from '@/types/notes';

// Only rebase a draft over the known pending → transcript transition, or over
// changes that left its text untouched. All other changes retain the base rev.
export function textEdit(base: Note, current: Note, draft: string) {
  const sameKind = base.kind === current.kind;
  const receivedTranscript = sameKind && base.pending && !current.pending && base.sourceId === current.sourceId && current.sentenceIds.length > base.sentenceIds.length;
  const prefix = base.owner === 'user' ? base.text.trim() : '';
  const transcript = !prefix ? current.text : current.text.startsWith(`${prefix}\n\n`) ? current.text.slice(prefix.length + 2) : null;
  if (receivedTranscript && transcript !== null) return { rev: current.rev, text: [draft.trim(), transcript].filter(Boolean).join('\n\n') };
  return { rev: sameKind && current.text === base.text ? current.rev : base.rev, text: draft };
}
