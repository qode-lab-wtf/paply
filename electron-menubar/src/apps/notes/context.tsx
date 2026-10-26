import { createContext, useContext } from 'react';
import type { NotesBoard, Note, NotesSource } from '@/types/notes';
export interface BoardContextValue { board: NotesBoard; selected: Set<string>; selectedEdges: Set<string>; editing: string|null; setEditing(id: string|null): void; finishEditing(id: string): Promise<void>; registerEditor(id: string, save: (() => Promise<boolean>)|null): void; command(ops: unknown[]): Promise<void>; source(id: string): void; notify(message: string): void; zoom: number }
export const BoardContext = createContext<BoardContextValue>(null!);
export const useBoard = () => useContext(BoardContext);
