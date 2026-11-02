// The Storage subset the apps use: upload bytes, sign a URL for a private
// object, serve it, delete it, and serve public buckets directly.
//
// Bytes live in Postgres rather than on disk so there is one thing to reset and
// no stray files left behind. Signed URLs are random tokens in a table; real
// Storage signs a JWT, which would behave identically here for far more code.

import { randomBytes } from 'node:crypto';
import { asRole, asService } from './db.mjs';

/**
 * Uploads an object.
 *
 * Runs as the caller so the `storage.objects` policies apply — which is the
 * point: a student uploading outside their own uuid prefix must be refused
 * here exactly as it would be in production.
 */
export async function upload({ claims, bucket, name, bytes, contentType, upsert }) {
  await asRole(claims, async ({ query }) => {
    const existing = await query(
      'select id from storage.objects where bucket_id = $1 and name = $2',
      [bucket, name],
    );

    if (existing.rows.length > 0 && !upsert) {
      const error = new Error('The resource already exists');
      error.status = 409;
      throw error;
    }

    if (existing.rows.length > 0) {
      await query(
        'update storage.objects set metadata = $3 where bucket_id = $1 and name = $2',
        [bucket, name, JSON.stringify({ mimetype: contentType, size: bytes.length })],
      );
    } else {
      // The insert is what the RLS policy gates, so it must be the caller's.
      await query(
        `insert into storage.objects (bucket_id, name, owner, metadata)
         values ($1, $2, $3, $4::jsonb)`,
        [
          bucket,
          name,
          claims?.sub ?? null,
          JSON.stringify({ mimetype: contentType, size: bytes.length }),
        ],
      );
    }
  });

  // The bytes themselves are not policy-gated — the row above already was.
  await asService(({ query }) =>
    query(
      `insert into storage.object_bytes (bucket_id, name, mime, bytes)
       values ($1, $2, $3, $4)
       on conflict (bucket_id, name) do update
         set bytes = excluded.bytes, mime = excluded.mime`,
      [bucket, name, contentType ?? null, bytes],
    ),
  );

  return { Key: `${bucket}/${name}`, path: name };
}

/** Issues a time-limited URL, having first checked the caller may read it. */
export async function createSignedUrl({ claims, bucket, name, expiresIn }) {
  const visible = await asRole(claims, async ({ query }) => {
    const found = await query(
      'select id from storage.objects where bucket_id = $1 and name = $2',
      [bucket, name],
    );
    return found.rows.length > 0;
  });

  if (!visible) {
    const error = new Error('Object not found');
    error.status = 404;
    throw error;
  }

  const token = randomBytes(24).toString('base64url');
  await asService(({ query }) =>
    query(
      `insert into storage.signed_urls (token, bucket_id, name, expires_at)
       values ($1, $2, $3, now() + make_interval(secs => $4))`,
      [token, bucket, name, Number(expiresIn) || 3600],
    ),
  );

  return `/storage/v1/object/sign/${bucket}/${name}?token=${token}`;
}

export async function readSigned(token) {
  return asService(async ({ query }) => {
    const found = await query(
      `select b.bucket_id, b.name, b.mime, b.bytes
         from storage.signed_urls s
         join storage.object_bytes b
           on b.bucket_id = s.bucket_id and b.name = s.name
        where s.token = $1 and s.expires_at > now()`,
      [token],
    );
    return found.rows[0] ?? null;
  });
}

/** Public buckets are readable without a token, as in production. */
export async function readPublic(bucket, name) {
  return asService(async ({ query }) => {
    const isPublic = await query(
      'select public from storage.buckets where id = $1',
      [bucket],
    );
    if (!isPublic.rows[0]?.public) return null;

    const found = await query(
      'select bucket_id, name, mime, bytes from storage.object_bytes where bucket_id = $1 and name = $2',
      [bucket, name],
    );
    return found.rows[0] ?? null;
  });
}

export async function remove({ claims, bucket, names }) {
  return asRole(claims, async ({ query }) => {
    const removed = [];
    for (const name of names) {
      const result = await query(
        'delete from storage.objects where bucket_id = $1 and name = $2 returning name',
        [bucket, name],
      );
      if (result.rows.length > 0) removed.push({ name });
    }
    return removed;
  });
}
