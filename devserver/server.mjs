// A local stand-in for Supabase.
//
// Point SUPABASE_URL at this and both apps run unchanged, against the project's
// real migrations, real RLS and real triggers. Nothing to sign up for, no
// Docker, no cloud project.
//
//   npm start            seeded demo data
//   npm start -- --empty no seed, so you can register from scratch

import { createServer } from 'node:http';
import { ANON_KEY, SERVICE_ROLE_KEY, verify } from './auth.mjs';
import * as auth from './auth.mjs';
import { coerceResult } from './coerce.mjs';
import { asRole, asService, initDatabase, raw } from './db.mjs';
import { introspect } from './introspect.mjs';
import { livekitEnv, signToken, NOT_CONFIGURED } from './livekit.mjs';
import {
  buildDeleteQuery,
  buildInsertQuery,
  buildRpcQuery,
  buildSelectQuery,
  buildUpdateQuery,
  parsePrefer,
} from './postgrest.mjs';
import { attachRealtime, broadcastChange } from './realtime.mjs';
import * as storage from './storage.mjs';
import { seed } from './seed.mjs';

const PORT = Number(process.env.PORT ?? 54321);
const skipSeed = process.argv.includes('--empty');

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, prefer, range, ' +
    'x-supabase-api-version, accept-profile, content-profile, x-upsert',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, PUT, DELETE, HEAD, OPTIONS',
  'Access-Control-Expose-Headers': 'content-range, content-length, x-supabase-api-version',
  'Access-Control-Max-Age': '86400',
};

// ── Helpers ─────────────────────────────────────────────────────────────────

function sendJson(res, status, body, extraHeaders = {}) {
  const payload = body === undefined ? '' : JSON.stringify(body);
  res.writeHead(status, {
    ...CORS,
    'Content-Type': 'application/json; charset=utf-8',
    ...extraHeaders,
  });
  res.end(payload);
}

function sendError(res, err) {
  const status = err.status ?? 500;
  // PostgREST's error shape, which both client libraries parse.
  const body = {
    message: err.message ?? 'Internal error',
    code: err.code ?? (err.status ? String(err.status) : 'XX000'),
    details: err.detail ?? null,
    hint: err.hint ?? null,
  };

  if (status >= 500) {
    console.error(`  ✗ ${body.code}: ${body.message}`);
    if (err.query) console.error(`    ${String(err.query).slice(0, 400)}`);
  }

  sendJson(res, status, body);
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return Buffer.concat(chunks);
}

async function readJson(req) {
  const buffer = await readBody(req);
  if (buffer.length === 0) return undefined;
  try {
    return JSON.parse(buffer.toString('utf8'));
  } catch {
    const error = new Error('Invalid JSON body');
    error.status = 400;
    throw error;
  }
}

/** The claims this request acts with, verified from the bearer token. */
function claimsFrom(req) {
  const header = req.headers.authorization ?? '';
  const bearer = header.replace(/^Bearer\s+/i, '').trim();
  const apikey = req.headers.apikey ?? '';

  // A user token takes precedence; the apikey alone means anon (or the
  // service role, which bypasses RLS exactly as the hosted key does).
  const token = bearer && bearer !== apikey ? bearer : bearer || apikey;
  const claims = verify(token);

  if (!claims) return null;
  if (claims.role === 'anon') return null;
  return claims;
}

/** Tables whose inserts and updates clients subscribe to. */
const BROADCAST_TABLES = new Set([
  'messages',
  'notifications',
  // Live Spaces. A student on the Spaces tab sees LIVE appear, and a host's
  // waiting list gains a row the moment someone arrives.
  'spaces',
  'space_participants',
  'space_messages',
]);

// ── Router ──────────────────────────────────────────────────────────────────

async function handle(req, res) {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const path = url.pathname;

  if (req.method === 'OPTIONS') {
    res.writeHead(204, CORS);
    res.end();
    return;
  }

  if (path === '/health' || path === '/') {
    sendJson(res, 200, {
      status: 'ok',
      service: 'lekkside-devserver',
      note: 'A local stand-in for Supabase, running the project migrations on PGlite.',
    });
    return;
  }

  if (path.startsWith('/auth/v1/')) return handleAuth(req, res, url);
  if (path.startsWith('/rest/v1/')) return handleRest(req, res, url);
  if (path.startsWith('/storage/v1/')) return handleStorage(req, res, url);
  if (path.startsWith('/functions/v1/')) return handleFunctions(req, res, url);

  sendJson(res, 404, { message: `No route for ${req.method} ${path}` });
}

// ── Auth ────────────────────────────────────────────────────────────────────

async function handleAuth(req, res, url) {
  const route = url.pathname.replace('/auth/v1/', '');

  try {
    if (route === 'token') {
      const grant = url.searchParams.get('grant_type');
      const body = (await readJson(req)) ?? {};

      if (grant === 'password') {
        return sendJson(res, 200, await auth.signInWithPassword(body));
      }
      if (grant === 'refresh_token') {
        return sendJson(res, 200, await auth.refresh(body.refresh_token));
      }
      const error = new Error(`Unsupported grant_type '${grant}'`);
      error.status = 400;
      throw error;
    }

    if (route === 'signup') {
      const body = (await readJson(req)) ?? {};
      return sendJson(res, 200, await auth.signUp(body));
    }

    if (route === 'user') {
      const claims = claimsFrom(req);
      if (req.method === 'PUT') {
        const body = (await readJson(req)) ?? {};
        return sendJson(res, 200, await auth.updateUser(claims, body));
      }
      const user = await auth.getUser(claims);
      if (!user) {
        const error = new Error('invalid claim: missing sub claim');
        error.status = 401;
        throw error;
      }
      return sendJson(res, 200, user);
    }

    if (route === 'logout') {
      // Stateless tokens: the client simply discards it.
      res.writeHead(204, CORS);
      res.end();
      return;
    }

const RESEND_API_KEY =
  process.env.RESEND_API_KEY ?? '';
const RESEND_FROM =
  process.env.RESEND_FROM ?? 'Lekkside Connect <no-reply@educationfair.com.ng>';

async function trySendDevEmail({ email, subject, text, html }) {
  if (!email || !RESEND_API_KEY) return;
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: RESEND_FROM,
        to: [email],
        subject,
        html: html ?? `<p>${text}</p>`,
      }),
    });
    if (res.ok) {
      const data = await res.json();
      console.log(`  ✓ Resend email delivered to ${email} (id: ${data.id})`);
    } else {
      const err = await res.text();
      console.warn(`  ⚠ Resend delivery notice: ${err}`);
    }
  } catch (err) {
    console.warn(`  ⚠ Resend send error: ${err.message}`);
  }
}

    if (route === 'recover' || route === 'otp' || route === 'resend') {
      const body = (await readJson(req)) ?? {};
      const targetEmail = body.email;
      if (targetEmail) {
        console.log(`  ℹ  ${route} requested for ${targetEmail} — dispatching OTP via Resend.`);
        const devOtp = String(Math.floor(10000000 + Math.random() * 90000000));
        await trySendDevEmail({
          email: targetEmail,
          subject: `${devOtp} is your Lekkside verification code`,
          text: `Your verification code is ${devOtp}. It is valid for 1 hour.`,
          html: `<div style="font-family: -apple-system, sans-serif; max-width: 480px; margin: 0 auto; padding: 28px; border: 1px solid #e2e8f0; border-radius: 16px;">
            <h2 style="color: #0f172a; margin-top: 0; font-size: 20px;">Lekkside Connect</h2>
            <p style="color: #475569; font-size: 15px;">Your verification code for account setup is:</p>
            <div style="background: #0f172a; color: #ffffff; padding: 18px; border-radius: 12px; text-align: center; font-size: 30px; font-weight: bold; letter-spacing: 5px; font-family: monospace;">
              ${devOtp}
            </div>
            <p style="color: #94a3b8; font-size: 12px; margin-top: 20px;">This code is valid for 1 hour. Never share this code with anyone.</p>
          </div>`
        });
      }
      return sendJson(res, 200, {});
    }

    if (route === 'settings') {
      return sendJson(res, 200, {
        external: { email: true },
        disable_signup: false,
        mailer_autoconfirm: true,
      });
    }

    sendJson(res, 404, { message: `Unsupported auth route '${route}'` });
  } catch (err) {
    sendError(res, err);
  }
}

// ── REST ────────────────────────────────────────────────────────────────────

async function handleRest(req, res, url) {
  const target = url.pathname.replace('/rest/v1/', '');
  const claims = claimsFrom(req);
  const prefer = parsePrefer(req.headers.prefer);

  try {
    if (target.startsWith('rpc/')) {
      const name = target.slice(4);
      const body = (await readJson(req)) ?? {};
      const { sql, params, isSet } = buildRpcQuery(name, body);

      const result = await asRole(claims, ({ query }) => query(sql, params));

      // A set-returning function answers with an array of rows, as PostgREST
      // does; a scalar one answers with its single value.
      if (isSet) {
        return sendJson(res, 200, coerceResult(result));
      }
      return sendJson(res, 200, result.rows[0]?.result ?? null);
    }

    const table = target;

    if (req.method === 'GET' || req.method === 'HEAD') {
      const { sql, params, countSql, countParams, limit, offset } = buildSelectQuery(
        table,
        url.searchParams,
        req.headers,
      );

      const wantsCount = String(prefer.count ?? '') !== '';
      const { rows, total } = await asRole(claims, async ({ query }) => {
        const head = req.method === 'HEAD';
        const data = head ? null : await query(sql, params);
        const counted =
          wantsCount || head ? await query(countSql, countParams) : null;
        return {
          rows: data ? coerceResult(data, table) : [],
          total: counted?.rows[0]?.count ?? null,
        };
      });

      const headers = {};
      if (total !== null) {
        const from = offset ?? 0;
        const to = rows.length > 0 ? from + rows.length - 1 : from;
        headers['Content-Range'] = `${from}-${to}/${total}`;
      }

      if (req.method === 'HEAD') {
        res.writeHead(200, { ...CORS, ...headers, 'Content-Type': 'application/json' });
        res.end();
        return;
      }

      // `.single()` / `.maybeSingle()` ask for an object, not an array.
      const accept = String(req.headers.accept ?? '');
      if (accept.includes('vnd.pgrst.object')) {
        if (rows.length === 0) {
          const error = new Error('The result contains 0 rows');
          error.status = 406;
          error.code = 'PGRST116';
          throw error;
        }
        if (rows.length > 1) {
          const error = new Error(
            `The result contains ${rows.length} rows, but one was expected`,
          );
          error.status = 406;
          error.code = 'PGRST114';
          throw error;
        }
        return sendJson(res, 200, rows[0], headers);
      }

      return sendJson(res, 200, rows, headers);
    }

    if (req.method === 'POST') {
      const body = await readJson(req);
      const { sql, params, returning } = buildInsertQuery(
        table,
        body,
        url.searchParams,
        req.headers,
        prefer,
      );

      const rows = await asRole(claims, async ({ query }) => {
        const result = await query(sql, params);
        return coerceResult(result, table);
      });

      // Tell any subscriber what just landed. Hosted Supabase reads the WAL;
      // here the write passed through this process, so it can just say so.
      if (BROADCAST_TABLES.has(table)) {
        const inserted = returning ? rows : await refetchInserted(table, body);
        for (const record of inserted) {
          broadcastChange({ table, type: 'INSERT', record });
        }
      }

      return respondToMutation(res, req, rows, returning, 201);
    }

    if (req.method === 'PATCH') {
      const body = await readJson(req);
      const { sql, params, returning } = buildUpdateQuery(
        table,
        body,
        url.searchParams,
        req.headers,
        prefer,
      );
      const rows = await asRole(claims, async ({ query }) => {
        const result = await query(sql, params);
        return coerceResult(result, table);
      });

      // Updates are broadcast too. The INSERT-only version was enough while
      // the only subscribed tables were append-only logs, but a space going
      // live is an UPDATE, and so is a participant being admitted.
      if (BROADCAST_TABLES.has(table) && returning) {
        for (const record of rows) {
          broadcastChange({ table, type: 'UPDATE', record });
        }
      }

      return respondToMutation(res, req, rows, returning, 200);
    }

    if (req.method === 'DELETE') {
      const { sql, params, returning } = buildDeleteQuery(
        table,
        url.searchParams,
        req.headers,
        prefer,
      );
      const rows = await asRole(claims, async ({ query }) => {
        const result = await query(sql, params);
        return coerceResult(result, table);
      });
      return respondToMutation(res, req, rows, returning, 200);
    }

    sendJson(res, 405, { message: `${req.method} is not supported here` });
  } catch (err) {
    sendError(res, err);
  }
}

function respondToMutation(res, req, rows, returning, createdStatus) {
  if (!returning) {
    res.writeHead(201 === createdStatus ? 201 : 204, CORS);
    res.end();
    return;
  }

  const accept = String(req.headers.accept ?? '');
  if (accept.includes('vnd.pgrst.object')) {
    if (rows.length === 0) {
      const error = new Error('The result contains 0 rows');
      error.status = 406;
      error.code = 'PGRST116';
      throw error;
    }
    return sendJson(res, createdStatus, rows[0]);
  }
  return sendJson(res, createdStatus, rows);
}

/**
 * For a broadcast after an insert that did not ask for its rows back.
 *
 * Only reached for `messages` and `notifications`, both of which the apps
 * insert with `.select()` anyway — so in practice this is a fallback.
 */
async function refetchInserted(table, body) {
  const rows = Array.isArray(body) ? body : [body];
  return asService(async ({ query }) => {
    const found = [];
    for (const row of rows) {
      if (!row?.conversation_id && !row?.profile_id) continue;
      const result = await query(
        `select * from ${table} order by created_at desc limit 1`,
      );
      if (result.rows[0]) found.push(result.rows[0]);
    }
    return found;
  });
}

// ── Storage ─────────────────────────────────────────────────────────────────

async function handleStorage(req, res, url) {
  const route = url.pathname.replace('/storage/v1/', '');
  const claims = claimsFrom(req);

  try {
    // GET /object/sign/<bucket>/<path>?token=…
    if (route.startsWith('object/sign/') && req.method === 'GET') {
      const token = url.searchParams.get('token');
      const object = await storage.readSigned(token);
      if (!object) {
        const error = new Error('Object not found or the link has expired');
        error.status = 404;
        throw error;
      }
      res.writeHead(200, {
        ...CORS,
        'Content-Type': object.mime ?? 'application/octet-stream',
        'Content-Length': object.bytes.length,
      });
      res.end(Buffer.from(object.bytes));
      return;
    }

    // POST /object/sign/<bucket>/<path> — create a signed URL
    if (route.startsWith('object/sign/') && req.method === 'POST') {
      const [bucket, ...rest] = route.replace('object/sign/', '').split('/');
      const body = (await readJson(req)) ?? {};
      const signed = await storage.createSignedUrl({
        claims,
        bucket,
        name: rest.join('/'),
        expiresIn: body.expiresIn,
      });
      return sendJson(res, 200, { signedURL: signed, signedUrl: signed });
    }

    // GET /object/public/<bucket>/<path>
    if (route.startsWith('object/public/')) {
      const [bucket, ...rest] = route.replace('object/public/', '').split('/');
      const object = await storage.readPublic(bucket, rest.join('/'));
      if (!object) {
        const error = new Error('Object not found');
        error.status = 404;
        throw error;
      }
      res.writeHead(200, {
        ...CORS,
        'Content-Type': object.mime ?? 'application/octet-stream',
        'Content-Length': object.bytes.length,
      });
      res.end(Buffer.from(object.bytes));
      return;
    }

    // DELETE /object/<bucket>  with { prefixes: [...] }
    if (route.startsWith('object/') && req.method === 'DELETE') {
      const rest = route.replace('object/', '');
      const body = (await readJson(req)) ?? {};
      const [bucket, ...pathParts] = rest.split('/');
      const names =
        body.prefixes ?? (pathParts.length > 0 ? [pathParts.join('/')] : []);
      const removed = await storage.remove({ claims, bucket, names });
      return sendJson(res, 200, removed);
    }

    // POST / PUT /object/<bucket>/<path> — upload
    if (route.startsWith('object/') && (req.method === 'POST' || req.method === 'PUT')) {
      const [bucket, ...rest] = route.replace('object/', '').split('/');
      const name = rest.join('/');
      const bytes = await readBody(req);

      const result = await storage.upload({
        claims,
        bucket,
        name,
        bytes,
        contentType: req.headers['content-type'],
        upsert:
          req.method === 'PUT' ||
          String(req.headers['x-upsert'] ?? '').toLowerCase() === 'true',
      });
      return sendJson(res, 200, result);
    }

    sendJson(res, 404, { message: `Unsupported storage route '${route}'` });
  } catch (err) {
    sendError(res, err);
  }
}

// ── Edge Functions ──────────────────────────────────────────────────────────

async function handleFunctions(req, res, url) {
  const name = url.pathname.replace('/functions/v1/', '');
  const claims = claimsFrom(req);

  try {
    const body = (await readJson(req)) ?? {};

    // `compute-matches` is the one function the apps call on a normal path, and
    // its real work is a SQL function — so it runs for real here.
    if (name === 'compute-matches') {
      if (!claims?.sub) {
        const error = new Error('authentication required');
        error.status = 401;
        throw error;
      }
      const target = body.student_id ?? claims.sub;
      const result = await asRole(claims, ({ query }) =>
        query('select refresh_matches_for_student($1) as matched', [target]),
      );
      return sendJson(res, 200, {
        scope: 'student',
        matched: result.rows[0]?.matched ?? 0,
      });
    }

    // The other two send email, which this server cannot do. Returning a
    // truthful "not sent" beats silently pretending it worked.
    if (name === 'verify-institution-domain') {
      console.log(
        '  ℹ  verify-institution-domain is stubbed in the dev server. ' +
          'Use the admin console to mark an institution verified.',
      );
      return sendJson(res, 200, {
        error:
          'Domain verification needs email, which the dev server cannot send. ' +
          'Sign in to the admin console and approve the institution in the ' +
          'verification queue instead.',
      });
    }

    if (name === 'send-notification') {
      const { recipient_id: recipientId, kind, title, message, payload } = body;
      if (!recipientId || !kind || !title) {
        const error = new Error('recipient_id, kind and title are required');
        error.status = 400;
        throw error;
      }

      // Inserted as the service role, exactly as the real function does: the
      // sender is usually not the recipient, so no RLS insert policy allows it.
      const inserted = await asService(async ({ query }) => {
        const result = await query(
          `insert into notifications (profile_id, kind, title, body, payload)
           values ($1, $2, $3, $4, $5::jsonb) returning *`,
          [recipientId, kind, title, message ?? null, JSON.stringify(payload ?? {})],
        );
        return result.rows[0];
      });

      broadcastChange({ table: 'notifications', type: 'INSERT', record: inserted });
      return sendJson(res, 200, { id: inserted.id, emailed: false });
    }

    // LiveKit. Everything except the signature runs for real: the grant
    // functions are SQL, and this server runs the real schema. So the
    // authorization, the consent write and the audit row are all genuine, and
    // seeing the decision the schema reached is most of the point of running
    // this locally.
    if (name === 'livekit-token') {
      if (!claims?.sub) {
        const error = new Error('authentication required');
        error.status = 401;
        throw error;
      }

      const spaceId = body.space_id ?? null;
      const apptId = body.appointment_id ?? null;
      if (!spaceId === !apptId) {
        const error = new Error('pass exactly one of space_id or appointment_id');
        error.status = 400;
        throw error;
      }

      const result = await asRole(claims, ({ query }) =>
        spaceId
          ? query('select space_room_grant($1) as g', [spaceId])
          : query('select appointment_room_grant($1) as g', [apptId]),
      );
      const grant = result.rows[0].g;

      // 'closed' and 'pending' are normal states with nothing to sign.
      if (grant.admission !== 'admitted') return sendJson(res, 200, grant);

      const cfg = livekitEnv();
      if (!cfg) {
        console.log(
          '  ℹ  livekit-token: no LIVEKIT_* in the environment, so nothing was signed.',
        );
        return sendJson(res, 200, { ...grant, error: NOT_CONFIGURED });
      }

      return sendJson(res, 200, {
        ...grant,
        url: cfg.url,
        token: await signToken(cfg, grant),
        expires_in: grant.ttl_seconds,
      });
    }

    // Moderation runs its SQL for real too, so a removal, an admission and the
    // audit row are all testable here. What is missing locally is the half that
    // disconnects somebody from a room nobody is in.
    if (name === 'livekit-room') {
      if (!claims?.sub) {
        const error = new Error('authentication required');
        error.status = 401;
        throw error;
      }

      const action = body.action;
      const cfg = livekitEnv();

      if (action === 'go_live' || action === 'end') {
        const status = action === 'go_live' ? 'live' : 'ended';
        await asRole(claims, ({ query }) =>
          query('select space_set_status($1, $2::space_status)', [body.space_id, status]),
        );
        return sendJson(res, 200, {
          ok: true,
          status,
          room: `space_${body.space_id}`,
          livekit: false,
          ...(cfg ? {} : { error: NOT_CONFIGURED }),
        });
      }

      if (action === 'moderate') {
        const moderated = await asRole(claims, ({ query }) =>
          query('select space_moderate($1, $2::space_moderation_action, $3) as r', [
            body.participant_id,
            body.moderation,
            body.reason ?? null,
          ]),
        );
        return sendJson(res, 200, {
          ok: true,
          ...moderated.rows[0].r,
          livekit: false,
          ...(cfg ? {} : { error: NOT_CONFIGURED }),
        });
      }

      if (action === 'mute_all') {
        // The SQL half — who may silence the room, who is exempt and the audit
        // row — runs for real. The LiveKit half is the part that would
        // disconnect audio in a room nobody is in, so `count` is what came back
        // and `muted` is honestly zero.
        const silenced = await asRole(claims, ({ query }) =>
          query('select space_mute_all($1, $2) as r', [
            body.space_id,
            body.include_video === true,
          ]),
        );
        return sendJson(res, 200, {
          ok: true,
          ...silenced.rows[0].r,
          muted: 0,
          livekit: false,
          ...(cfg ? {} : { error: NOT_CONFIGURED }),
        });
      }

      if (action === 'participants') {
        // No room to list, so an empty list and a truthful flag. The database
        // roster is in space_roster, which the console reads directly.
        return sendJson(res, 200, { participants: [], livekit: false, error: NOT_CONFIGURED });
      }

      const error = new Error(
        'specify action: go_live, end, moderate, mute_all or participants',
      );
      error.status = 400;
      throw error;
    }

    sendJson(res, 404, { message: `No function named '${name}'` });
  } catch (err) {
    sendError(res, err);
  }
}

// ── Boot ────────────────────────────────────────────────────────────────────

async function main() {
  console.log('\nLekkside Connect — local dev server');
  console.log('  (a stand-in for Supabase; no Docker, no cloud project)\n');

  await initDatabase();
  const db = await raw();
  await introspect(db);

  if (skipSeed) {
    console.log('  --empty: no demo data, register from scratch');
  } else {
    const summary = await seed();
    console.log(
      `  seeded ${summary.students} students, ${summary.institutions} institutions, ` +
        `${summary.programs} programs, ${summary.matches} matches ` +
        `across ${summary.matchable} matchable passports, ` +
        `best institution page ${summary.best_profile}%, ${summary.posts} posts`,
    );
  }

  const server = createServer((req, res) => {
    handle(req, res).catch((err) => sendError(res, err));
  });

  attachRealtime(server);

  server.listen(PORT, () => {
    console.log(`
  Listening on  http://localhost:${PORT}

  Put these in student_app/.env:
    SUPABASE_URL=http://localhost:${PORT}
    SUPABASE_ANON_KEY=${ANON_KEY}

  …and in web/.env.local:
    VITE_SUPABASE_URL=http://localhost:${PORT}
    VITE_SUPABASE_ANON_KEY=${ANON_KEY}

  Service-role key (server-side only):
    ${SERVICE_ROLE_KEY.slice(0, 40)}…
${
  skipSeed
    ? ''
    : `
  Sign in with any of these — password  Lekkside123!

    Student      chidi.okeke@example.com
    Institution  admissions@maplecrest.ca
    Admin        admin@lekkside.com
`
}`);
  });
}

main().catch((err) => {
  console.error('\n  Failed to start:', err.message);
  process.exit(1);
});
