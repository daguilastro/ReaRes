import assert from 'node:assert/strict';
import test from 'node:test';
import { RoomRealtimeHub, type RoomSocket } from '../../shared/roomRealtime';

class FakeSocket implements RoomSocket {
  readyState = 1;
  messages: Array<Record<string, unknown>> = [];
  closed?: { code?: number; reason?: string };

  send(data: string) {
    this.messages.push(JSON.parse(data) as Record<string, unknown>);
  }

  close(code?: number, reason?: string) {
    this.closed = { code, reason };
    this.readyState = 3;
  }
}

test('real-time invalidations are scoped to the subscribed room', () => {
  const hub = new RoomRealtimeHub();
  const roomOne = new FakeSocket();
  const roomTwo = new FakeSocket();
  hub.connect(roomOne, 10);
  hub.connect(roomTwo, 20);
  hub.subscribe(roomOne, 1);
  hub.subscribe(roomTwo, 2);

  hub.publishRoomLayoutChanged(1);

  assert.equal(roomOne.messages.at(-1)?.type, 'room-layout-changed');
  assert.equal(roomOne.messages.at(-1)?.roomId, 1);
  assert.notEqual(roomTwo.messages.at(-1)?.type, 'room-layout-changed');
});

test('assignment changes target one employee and deletion closes their sockets', () => {
  const hub = new RoomRealtimeHub();
  const employee = new FakeSocket();
  const otherEmployee = new FakeSocket();
  hub.connect(employee, 10);
  hub.connect(otherEmployee, 20);

  hub.publishAssignmentsChanged(10);
  assert.equal(employee.messages.at(-1)?.type, 'room-assignments-changed');
  assert.notEqual(otherEmployee.messages.at(-1)?.type, 'room-assignments-changed');

  hub.disconnectUser(10);
  assert.equal(employee.closed?.code, 1008);
  assert.equal(otherEmployee.closed, undefined);
});
