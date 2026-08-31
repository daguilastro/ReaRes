import { DatabaseSync } from 'node:sqlite';

export type ActivityEvent = {
  id: number;
  author: string;
  type: string;
  modification: string;
  roomId: number | null;
  createdAt: string;
};

class ActivityHub {
  private readonly listeners = new Set<(event: ActivityEvent) => void>();

  subscribe(listener: (event: ActivityEvent) => void) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  publish(event: ActivityEvent) {
    for (const listener of this.listeners) listener(event);
  }
}

export const activityHub = new ActivityHub();

export function recordActivity(
  database: DatabaseSync,
  input: {
    authorId: number;
    author: string;
    roomId: number;
    type: string;
    modification: string;
  },
): ActivityEvent {
  const createdAt = new Date().toISOString();
  const result = database.prepare(
    `INSERT INTO activity_log
     (author_id, hall_id, type, modification, created_at)
     VALUES (?, ?, ?, ?, ?)`,
  ).run(input.authorId, input.roomId, input.type, input.modification, createdAt);
  return {
    id: Number(result.lastInsertRowid),
    author: input.author,
    type: input.type,
    modification: input.modification,
    roomId: input.roomId,
    createdAt,
  };
}
