// Realtime: enough of the Phoenix channel protocol for the clients' postgres
// change subscriptions to work.
//
// Hosted Supabase reads the WAL. Here every write goes through this server, so
// it can simply announce what it just inserted — which is less machinery and,
// for a dev server, indistinguishable from the real thing.
//
// Deliberately NOT re-checked against RLS before broadcasting: a subscriber is
// only sent changes on the table and filter it asked for, and both apps
// subscribe with a filter scoping to their own conversation or profile. That is
// a dev-server simplification, and the one place this differs from production,
// where Realtime applies RLS per subscriber.

import { WebSocketServer } from 'ws';

const sockets = new Set();

export function attachRealtime(server, { log = console.log } = {}) {
  const wss = new WebSocketServer({ server, path: '/realtime/v1/websocket' });

  wss.on('connection', (socket) => {
    const state = { socket, topics: new Map() };
    sockets.add(state);

    socket.on('message', (raw) => {
      let frame;
      try {
        frame = JSON.parse(raw.toString());
      } catch {
        return;
      }

      const { topic, event, payload, ref } = frame;

      // The client's keepalive, on its own topic.
      if (topic === 'phoenix' && event === 'heartbeat') {
        send(socket, { topic, event: 'phx_reply', ref, payload: { status: 'ok', response: {} } });
        return;
      }

      if (event === 'phx_join') {
        // `postgres_changes` config describes what the subscriber wants. The
        // server echoes it back with ids, which is what the client waits for
        // before reporting SUBSCRIBED.
        const requested =
          payload?.config?.postgres_changes ?? payload?.configs?.postgres_changes ?? [];

        state.topics.set(
          topic,
          requested.map((config, index) => ({ ...config, id: index + 1 })),
        );

        send(socket, {
          topic,
          event: 'phx_reply',
          ref,
          payload: {
            status: 'ok',
            response: {
              postgres_changes: state.topics.get(topic),
            },
          },
        });
        return;
      }

      if (event === 'phx_leave') {
        state.topics.delete(topic);
        send(socket, { topic, event: 'phx_reply', ref, payload: { status: 'ok', response: {} } });
        return;
      }

      // access_token refreshes and anything else: acknowledge and move on.
      if (ref) {
        send(socket, { topic, event: 'phx_reply', ref, payload: { status: 'ok', response: {} } });
      }
    });

    socket.on('close', () => sockets.delete(state));
    socket.on('error', () => sockets.delete(state));
  });

  log('  realtime listening on /realtime/v1/websocket');
  return wss;
}

function send(socket, frame) {
  if (socket.readyState === socket.OPEN) {
    socket.send(JSON.stringify(frame));
  }
}

/** Announces a row change to every subscriber whose filter matches. */
export function broadcastChange({ schema = 'public', table, type, record, oldRecord }) {
  for (const state of sockets) {
    for (const [topic, configs] of state.topics.entries()) {
      for (const config of configs) {
        if (config.schema && config.schema !== schema) continue;
        if (config.table && config.table !== table) continue;
        if (config.event && config.event !== '*' && config.event !== type) continue;
        if (config.filter && !matchesFilter(config.filter, record)) continue;

        send(state.socket, {
          topic,
          event: 'postgres_changes',
          payload: {
            ids: [config.id],
            data: {
              schema,
              table,
              commit_timestamp: new Date().toISOString(),
              eventType: type,
              type,
              record: record ?? {},
              old_record: oldRecord ?? {},
              errors: null,
            },
          },
          ref: null,
        });
      }
    }
  }
}

/** Only `column=eq.value` is used by either app. */
function matchesFilter(filter, record) {
  const match = /^([A-Za-z0-9_]+)=eq\.(.*)$/.exec(filter);
  if (!match) return true;
  const [, column, value] = match;
  return String(record?.[column] ?? '') === value;
}
