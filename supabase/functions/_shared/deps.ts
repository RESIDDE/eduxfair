// Shared helpers for the Lekkside Connect Edge Functions.
//
// Only three functions exist, not the five originally planned: the fair scan
// and the fair report ended up as SQL functions (record_booth_visit,
// fair_report) because both are single-transaction database work, and a
// PostgREST RPC call reaches them directly with no extra deployment surface.

import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

export type { SupabaseClient };

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

export function preflight(req: Request): Response | null {
  return req.method === 'OPTIONS' ? new Response('ok', { headers: corsHeaders }) : null;
}

/** Service-role client. Bypasses RLS — only for work the caller is already authorized to do. */
export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );
}

/**
 * A client acting AS the caller, so every query stays inside their RLS. This is
 * the default: reaching for adminClient() should be a deliberate decision, not
 * the path of least resistance.
 */
export function callerClient(req: Request): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
      auth: { persistSession: false },
    },
  );
}

/** Resolves the calling user, or null when the request carries no valid JWT. */
export async function requireUser(req: Request) {
  const supabase = callerClient(req);
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) return null;
  return data.user;
}

/** Sends an email through Resend. No-ops (loudly) when the key is absent. */
export async function sendEmail(opts: {
  to: string;
  subject: string;
  html: string;
}): Promise<{ ok: boolean; detail?: string }> {
  const key =
    Deno.env.get('RESEND_API_KEY') ?? '';
  const from =
    Deno.env.get('RESEND_FROM') ??
    'Lekkside Connect <no-reply@educationfair.com.ng>';

  if (!key) {
    console.warn('RESEND_API_KEY is not set — email not sent:', opts.subject);
    return { ok: false, detail: 'email not configured' };
  }

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from, to: [opts.to], subject: opts.subject, html: opts.html }),
  });

  if (!res.ok) {
    const detail = await res.text();
    console.error('Resend rejected the send:', res.status, detail);
    return { ok: false, detail };
  }
  return { ok: true };
}
