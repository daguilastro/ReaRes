export type RoomSocket = {
  readonly readyState: number;
  send(data: string): void;
  close(code?: number, reason?: string): void;
};

type Connection = {
  userId: number;
  rooms: Set<number>;
};

export class RoomRealtimeHub {
  private readonly connections = new Map<RoomSocket, Connection>();

  connect(socket: RoomSocket, userId: number) {
    this.connections.set(socket, { userId, rooms: new Set() });
    socket.send(JSON.stringify({ type: 'connected' }));
  }

  disconnect(socket: RoomSocket) {
    this.connections.delete(socket);
  }

  subscribe(socket: RoomSocket, roomId: number) {
    const connection = this.connections.get(socket);
    if (!connection) return;
    connection.rooms.add(roomId);
    socket.send(JSON.stringify({ type: 'subscribed', roomId }));
  }

  unsubscribe(socket: RoomSocket, roomId: number) {
    this.connections.get(socket)?.rooms.delete(roomId);
  }

  publishRoomLayoutChanged(roomId: number) {
    this.publish(
      (connection) => connection.rooms.has(roomId),
      { type: 'room-layout-changed', roomId, occurredAt: new Date().toISOString() },
    );
  }

  publishRoomOrdersChanged(roomId: number) {
    this.publish(
      (connection) => connection.rooms.has(roomId),
      { type: 'room-orders-changed', roomId, occurredAt: new Date().toISOString() },
    );
  }

  publishAssignmentsChanged(userId: number) {
    this.publish(
      (connection) => connection.userId === userId,
      { type: 'room-assignments-changed', occurredAt: new Date().toISOString() },
    );
  }

  disconnectUser(userId: number) {
    for (const [socket, connection] of this.connections) {
      if (connection.userId !== userId) continue;
      this.connections.delete(socket);
      try {
        socket.close(1008, 'Employee account is no longer available');
      } catch {
        // La conexión ya estaba cerrada.
      }
    }
  }

  private publish(
    accepts: (connection: Connection) => boolean,
    event: Record<string, unknown>,
  ) {
    const message = JSON.stringify(event);
    for (const [socket, connection] of this.connections) {
      if (socket.readyState !== 1 || !accepts(connection)) continue;
      try {
        socket.send(message);
      } catch {
        this.connections.delete(socket);
      }
    }
  }
}

export const roomRealtimeHub = new RoomRealtimeHub();
