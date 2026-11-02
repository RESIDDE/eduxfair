// The GoTrue subset both apps use: sign up, sign in with a password, refresh,
// read the current user, and sign out.
//
// Tokens are real HS256 JWTs signed with a local dev secret. That matters for
// more than realism: the claims are what `asRole` feeds into
// `request.jwt.claims`, which is what auth.uid() reads, which is what every
// RLS policy depends on. A fake token would mean fake authorization.

import { createHmac, randomBytes, randomUUID, scryptSync, timingSafeEqual } from 'node:crypto';
import { asService } from './db.mjs';

// Fixed so tokens survive a restart and the anon key can be printed in a
// README. A dev-only secret, never used anywhere real.
export const JWT_SECRET = 'lekkside-devserver-secret-not-for-production';

const ACCESS_TOKEN_TTL = 60 * 60; // an hour, like hosted Supabase

const base64url = (input) =>
  Buffer.from(input).toString('base64url');

function sign(payload) {
  const header = base64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = base64url(JSON.stringify(payload));
  const signature = createHmac('sha256', JWT_SECRET)
    .update(`${header}.${body}`)
    .digest('base64url');
  return `${header}.${body}.${signature}`;
}

/** Returns the claims, or null when the token is missing, malformed or expired. */
export function verify(token) {
  if (!token) return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;

  const [header, body, signature] = parts;
  const expected = createHmac('sha256', JWT_SECRET)
    .update(`${header}.${body}`)
    .digest('base64url');

  // Constant-time compare, out of habit rather than necessity here.
  const a = Buffer.from(signature);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null;

  let claims;
  try {
    claims = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
  } catch {
    return null;
  }

  if (claims.exp && claims.exp < Math.floor(Date.now() / 1000)) return null;
  return claims;
}

/** The long-lived anon key clients send as `apikey`. */
export const ANON_KEY = sign({
  iss: 'lekkside-devserver',
  role: 'anon',
  // Ten years: this is a published dev constant, not a credential.
  exp: Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 365 * 10,
});

export const SERVICE_ROLE_KEY = sign({
  iss: 'lekkside-devserver',
  role: 'service_role',
  exp: Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 365 * 10,
});

// ── Passwords ───────────────────────────────────────────────────────────────

export function hashPassword(password) {
  const salt = randomBytes(16).toString('hex');
  const derived = scryptSync(password, salt, 32).toString('hex');
  return `scrypt$${salt}$${derived}`;
}

function verifyPassword(password, stored) {
  if (!stored?.startsWith('scrypt$')) return false;
  const [, salt, expected] = stored.split('$');
  const derived = scryptSync(password, salt, 32).toString('hex');
  const a = Buffer.from(derived);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

// ── User records ────────────────────────────────────────────────────────────

function sessionFor(user) {
  const now = Math.floor(Date.now() / 1000);
  const accessToken = sign({
    iss: 'lekkside-devserver',
    sub: user.id,
    email: user.email,
    role: 'authenticated',
    aud: 'authenticated',
    iat: now,
    exp: now + ACCESS_TOKEN_TTL,
    user_metadata: user.raw_user_meta_data ?? {},
  });

  return {
    access_token: accessToken,
    token_type: 'bearer',
    expires_in: ACCESS_TOKEN_TTL,
    expires_at: now + ACCESS_TOKEN_TTL,
    // The dev server does not rotate refresh tokens; the client just presents
    // this back and gets a fresh access token for the same user.
    refresh_token: `dev-refresh-${user.id}`,
    user: publicUser(user),
  };
}

export function publicUser(user) {
  return {
    id: user.id,
    aud: 'authenticated',
    role: 'authenticated',
    email: user.email,
    email_confirmed_at: user.email_confirmed_at ?? new Date().toISOString(),
    phone: '',
    confirmed_at: user.email_confirmed_at ?? new Date().toISOString(),
    last_sign_in_at: user.last_sign_in_at ?? new Date().toISOString(),
    app_metadata: { provider: 'email', providers: ['email'] },
    user_metadata: user.raw_user_meta_data ?? {},
    identities: [],
    created_at: user.created_at,
    updated_at: user.created_at,
  };
}

/**
 * Creates a user. The `on_auth_user_created` trigger mirrors it into
 * `profiles`, clamping the requested role — so 'admin' still cannot be
 * self-assigned at signup, exactly as in production.
 */
export async function createUser({ email, password, metadata = {} }) {
  const normalised = email.trim().toLowerCase();

  return asService(async ({ query }) => {
    const existing = await query('select id from auth.users where email = $1', [
      normalised,
    ]);
    if (existing.rows.length > 0) {
      const error = new Error('User already registered');
      error.status = 422;
      error.code = 'user_already_exists';
      throw error;
    }

    const id = randomUUID();
    await query(
      `insert into auth.users
         (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
       values ($1, $2, $3, now(), $4::jsonb)`,
      [id, normalised, hashPassword(password), JSON.stringify(metadata)],
    );
    await query(
      // `user_id` is uuid and `provider_id` is text, so the id is bound twice
      // rather than reused as `$1::text`: one placeholder in two positions
      // makes Postgres deduce two types for it and reject the statement
      // outright ("inconsistent types deduced for parameter $1"). This is the
      // only path that creates an account at runtime — seed.mjs has always
      // bound it twice — so until now every sign-up through the app failed.
      `insert into auth.identities (user_id, provider, provider_id, identity_data)
       values ($1, 'email', $2, $3::jsonb)`,
      [id, id, JSON.stringify({ sub: id, email: normalised, email_verified: true })],
    );

    const created = await query('select * from auth.users where id = $1', [id]);
    return created.rows[0];
  });
}

export async function signInWithPassword({ email, password }) {
  const normalised = (email ?? '').trim().toLowerCase();

  const user = await asService(async ({ query }) => {
    const found = await query('select * from auth.users where email = $1', [normalised]);
    return found.rows[0] ?? null;
  });

  // The same message either way: whether an address has an account is not
  // something an unauthenticated caller should be able to probe.
  if (!user || !verifyPassword(password ?? '', user.encrypted_password)) {
    const error = new Error('Invalid login credentials');
    error.status = 400;
    error.code = 'invalid_credentials';
    throw error;
  }

  await asService(({ query }) =>
    query('update auth.users set last_sign_in_at = now() where id = $1', [user.id]),
  );

  return sessionFor(user);
}

export async function signUp({ email, password, data = {} }) {
  const user = await createUser({ email, password, metadata: data });
  // Email confirmation is off in the dev server, so a session comes straight
  // back and the apps skip their OTP branch.
  return sessionFor(user);
}

export async function refresh(refreshToken) {
  const id = String(refreshToken ?? '').replace(/^dev-refresh-/, '');

  const user = await asService(async ({ query }) => {
    const found = await query('select * from auth.users where id = $1', [id]);
    return found.rows[0] ?? null;
  });

  if (!user) {
    const error = new Error('Invalid Refresh Token');
    error.status = 400;
    error.code = 'invalid_grant';
    throw error;
  }
  return sessionFor(user);
}

export async function getUser(claims) {
  if (!claims?.sub) return null;
  return asService(async ({ query }) => {
    const found = await query('select * from auth.users where id = $1', [claims.sub]);
    return found.rows[0] ? publicUser(found.rows[0]) : null;
  });
}

export async function updateUser(claims, { password, data }) {
  if (!claims?.sub) {
    const error = new Error('Not authenticated');
    error.status = 401;
    throw error;
  }

  return asService(async ({ query }) => {
    if (password) {
      await query('update auth.users set encrypted_password = $1 where id = $2', [
        hashPassword(password),
        claims.sub,
      ]);
    }
    if (data) {
      await query(
        `update auth.users
            set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || $1::jsonb
          where id = $2`,
        [JSON.stringify(data), claims.sub],
      );
    }
    const found = await query('select * from auth.users where id = $1', [claims.sub]);
    return publicUser(found.rows[0]);
  });
}
