// Edge Function: send-auth-email
//
// Sends branded authentication emails (custom 6-digit OTP verification codes) via Resend.
// Completely bypasses Supabase Auth's built-in mailer to prevent email rate limits.
//
// Actions:
// - signup: Creates user via Admin API (email_confirm: true), dispatches custom OTP via Resend.
// - send_recovery_otp: Generates password reset OTP and sends via Resend.
// - reset_password: Validates OTP and updates user's password via Admin API.
// - send: Generates OTP and sends via Resend.
// - verify: Validates OTP against account_otps.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

const RESEND_API_KEY =
  Deno.env.get("RESEND_API_KEY") ?? "";
const RESEND_FROM =
  Deno.env.get("RESEND_FROM") ??
  "Eduxfair <no-reply@educationfair.com.ng>";

const SUPABASE_URL =
  Deno.env.get("SUPABASE_URL") ?? "https://escjlnqgruwnaepoeivc.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

function getSupabaseClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

function buildOtpEmailHtml({
  code,
  actionType,
  recipientEmail,
}: {
  code: string;
  actionType: string;
  recipientEmail: string;
}): string {
  const isRecovery = actionType === "recovery" || actionType === "reset";
  const title = isRecovery ? "Reset your password" : "Verify your email";
  const subtitle = isRecovery
    ? "You requested a password reset code for your Eduxfair account. Enter the 6-digit code below to set a new password."
    : "Welcome to Eduxfair. Please confirm your email address to complete your account setup.";
  const securityNote = isRecovery
    ? "This code is valid for 15 minutes. If you did not request a password reset, please disregard this email."
    : "This code is valid for 15 minutes. Never share this code with anyone. Eduxfair staff will never ask for your code.";

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title}</title>
  <style>
    body {
      margin: 0;
      padding: 0;
      background-color: #f7f9fa;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      color: #111827;
      -webkit-font-smoothing: antialiased;
    }
    .wrapper {
      width: 100%;
      background-color: #f7f9fa;
      padding: 48px 16px;
      box-sizing: border-box;
    }
    .container {
      max-width: 520px;
      margin: 0 auto;
      background-color: #ffffff;
      border-radius: 20px;
      padding: 40px 36px;
      box-shadow: 0 4px 24px rgba(0, 0, 0, 0.05);
      border: 1px solid #e5e7eb;
    }
    .brand {
      text-align: center;
      margin-bottom: 28px;
    }
    .brand-title {
      font-size: 22px;
      font-weight: 800;
      color: #0d1527;
      letter-spacing: -0.5px;
      margin: 0;
    }
    .brand-badge {
      display: inline-block;
      margin-top: 6px;
      font-size: 11px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.8px;
      background-color: #f0f4ff;
      color: #2563eb;
      padding: 3px 10px;
      border-radius: 99px;
    }
    h1 {
      font-size: 24px;
      font-weight: 700;
      color: #111827;
      margin: 0 0 10px;
      text-align: center;
      letter-spacing: -0.4px;
    }
    p.lead {
      font-size: 15px;
      line-height: 1.55;
      color: #4b5563;
      margin: 0 0 28px;
      text-align: center;
    }
    .otp-card {
      background: linear-gradient(135deg, #0d1527 0%, #1e293b 100%);
      border-radius: 16px;
      padding: 26px 20px;
      text-align: center;
      margin-bottom: 28px;
      box-shadow: 0 6px 20px rgba(13, 21, 39, 0.15);
    }
    .otp-label {
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 1.5px;
      color: #94a3b8;
      margin-bottom: 8px;
    }
    .otp-code {
      font-size: 36px;
      font-weight: 800;
      letter-spacing: 8px;
      color: #ffffff;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      margin: 0;
      padding: 0;
    }
    .notice {
      background-color: #f8fafc;
      border-left: 3px solid #2563eb;
      border-radius: 0 8px 8px 0;
      padding: 12px 16px;
      margin-bottom: 28px;
      font-size: 13px;
      line-height: 1.5;
      color: #475569;
    }
    .footer {
      border-top: 1px solid #f1f5f9;
      padding-top: 24px;
      text-align: center;
      font-size: 12px;
      color: #9ca3af;
      line-height: 1.6;
    }
    .footer a {
      color: #6b7280;
      text-decoration: underline;
    }
  </style>
</head>
<body>
  <div class="wrapper">
    <div class="container">
      <div class="brand">
        <h2 class="brand-title">Eduxfair</h2>
        <span class="brand-badge">Education Passport</span>
      </div>

      <h1>${title}</h1>
      <p class="lead">${subtitle}</p>

      <div class="otp-card">
        <div class="otp-label">Verification Code</div>
        <div class="otp-code">${code}</div>
      </div>

      <div class="notice">
        <strong>Security note:</strong> ${securityNote}
      </div>

      <div class="footer">
        Sent to <span style="color: #374151;">${recipientEmail}</span><br>
        &copy; ${new Date().getFullYear()} Eduxfair. All rights reserved.
      </div>
    </div>
  </div>
</body>
</html>`;
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, webhook-id, webhook-timestamp, webhook-signature",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: CORS_HEADERS,
    });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  try {
    const payload = await req.json().catch(() => ({}));
    const action = String(payload.action ?? "").toLowerCase();

    const recipientEmail = String(
      payload.email ||
      payload.user?.email ||
      payload.recipient ||
      ""
    ).trim();

    if (!recipientEmail) {
      return new Response(
        JSON.stringify({ ok: false, error: "Email address is required." }),
        {
          status: 400,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        }
      );
    }

    const supabase = getSupabaseClient();

    // ── Action: signup ────────────────────────────────────────────────────────
    // Creates user via Admin API with email_confirm: true so Supabase never emails.
    // Automatically sets profiles.email_verified = false and sends Resend OTP.
    if (action === "signup") {
      const password = String(payload.password ?? "");
      const fullName = String(payload.fullName ?? "").trim();
      const role = String(payload.role ?? "student").trim();
      const country = payload.country ? String(payload.country).trim() : null;
      // ISO date, age-verification only. The database carries a CHECK that
      // refuses anyone under sixteen, so a client that skips the picker
      // cannot create an underage account by calling this directly.
      const dateOfBirth = payload.dateOfBirth
        ? String(payload.dateOfBirth).trim()
        : null;

      if (!password || password.length < 8) {
        return new Response(
          JSON.stringify({ ok: false, error: "Password must be at least 8 characters long." }),
          {
            status: 400,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          }
        );
      }

      // Check if user already exists
      const { data: existingUserId } = await supabase.rpc("lookup_user_by_email", {
        p_email: recipientEmail,
      });

      if (existingUserId) {
        return new Response(
          JSON.stringify({
            ok: false,
            error: "An account with this email address already exists. Please sign in.",
          }),
          {
            status: 409,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          }
        );
      }

      // Create account via Admin API with email_confirm: true to bypass Supabase mailer
      const { data: authData, error: createError } = await supabase.auth.admin.createUser({
        email: recipientEmail,
        password: password,
        email_confirm: true,
        user_metadata: {
          role,
          full_name: fullName,
        },
      });

      if (createError) {
        console.error("Admin createUser error:", createError);
        return new Response(
          JSON.stringify({ ok: false, error: createError.message }),
          {
            status: 400,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          }
        );
      }

      const createdUserId = authData.user?.id;
      if (createdUserId) {
        // Ensure email_verified starts false
        await supabase
          .from("profiles")
          .update({
            email_verified: false,
            ...(country ? { country } : {}),
            ...(dateOfBirth ? { date_of_birth: dateOfBirth } : {}),
          })
          .eq("id", createdUserId);
      }

      // Generate custom 6-digit OTP
      const { data: code, error: genError } = await supabase.rpc("generate_account_otp", {
        p_email: recipientEmail,
      });

      if (genError) {
        console.error("Failed to generate signup OTP:", genError);
        return new Response(
          JSON.stringify({
            ok: false,
            error: genError.message || "Account created, but could not send verification code.",
          }),
          {
            status: 500,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          }
        );
      }

      const htmlContent = buildOtpEmailHtml({
        code: String(code).trim(),
        actionType: "signup",
        recipientEmail,
      });

      await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${RESEND_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: RESEND_FROM,
          to: [recipientEmail],
          subject: `${code} is your Eduxfair verification code`,
          html: htmlContent,
        }),
      });

      return new Response(
        JSON.stringify({
          ok: true,
          message: "Account created successfully. Verification code sent.",
          userId: createdUserId,
        }),
        {
          status: 200,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        }
      );
    }

    // ── Action: send_recovery_otp ─────────────────────────────────────────────
    if (action === "send_recovery_otp") {
      const { data: userId } = await supabase.rpc("lookup_user_by_email", {
        p_email: recipientEmail,
      });

      if (!userId) {
        // Return generic success to prevent email enumeration
        return new Response(
          JSON.stringify({
            ok: true,
            message: "If an account exists, a verification code has been sent.",
          }),
          {
            status: 200,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          }
        );
      }

      const { data: code, error: genError } = await supabase.rpc("generate_account_otp", {
        p_email: recipientEmail,
      });

      if (genError) {
        console.error("Failed to generate recovery OTP:", genError);
        return new Response(
          JSON.stringify({ ok: false, error: genError.message }),
          {
            status: 400,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          }
        );
      }

      const htmlContent = buildOtpEmailHtml({
        code: String(code).trim(),
        actionType: "recovery",
        recipientEmail,
      });

      const resendResponse = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${RESEND_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: RESEND_FROM,
          to: [recipientEmail],
          subject: `${code} is your Eduxfair password reset code`,
          html: htmlContent,
        }),
      });

      if (!resendResponse.ok) {
        const resendErr = await resendResponse.json();
        console.error("Resend delivery failed:", resendErr);
        return new Response(
          JSON.stringify({ ok: false, error: "Failed to deliver reset email." }),
          {
            status: 500,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          }
        );
      }

      return new Response(
        JSON.stringify({
          ok: true,
          message: "Password reset code sent successfully.",
        }),
        {
          status: 200,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        }
      );
    }

    // ── Action: reset_password ────────────────────────────────────────────────
    if (action === "reset_password") {
      const code = String(payload.code ?? "").trim();
      const newPassword = String(payload.newPassword ?? "");

      if (!code) {
        return new Response(
          JSON.stringify({ ok: false, error: "Verification code is required." }),
          {
            status: 400,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          }
        );
      }

      if (!newPassword || newPassword.length < 8) {
        return new Response(
          JSON.stringify({ ok: false, error: "Password must be at least 8 characters long." }),
          {
            status: 400,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          }
        );
      }

      // Verify OTP code
      const { data: verifyData, error: verifyErr } = await supabase.rpc("verify_account_otp", {
        p_email: recipientEmail,
        p_code: code,
      });

      if (verifyErr || !verifyData || verifyData.ok !== true) {
        return new Response(
          JSON.stringify({
            ok: false,
            error: verifyData?.error || verifyErr?.message || "Invalid or expired code.",
          }),
          {
            status: 400,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          }
        );
      }

      // Find user ID
      const { data: userId } = await supabase.rpc("lookup_user_by_email", {
        p_email: recipientEmail,
      });

      if (!userId) {
        return new Response(
          JSON.stringify({ ok: false, error: "User account not found." }),
          {
            status: 404,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          }
        );
      }

      // Update password via Admin API
      const { error: updateErr } = await supabase.auth.admin.updateUserById(userId, {
        password: newPassword,
      });

      if (updateErr) {
        console.error("Failed to update password:", updateErr);
        return new Response(
          JSON.stringify({ ok: false, error: updateErr.message }),
          {
            status: 500,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          }
        );
      }

      return new Response(
        JSON.stringify({
          ok: true,
          message: "Password reset successfully. You can now sign in.",
        }),
        {
          status: 200,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        }
      );
    }

    // ── Action: verify ────────────────────────────────────────────────────────
    if (action === "verify") {
      const code = payload.code || payload.token;
      if (!code) {
        return new Response(
          JSON.stringify({ ok: false, error: "Verification code is required." }),
          {
            status: 400,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          }
        );
      }

      const { data, error } = await supabase.rpc("verify_account_otp", {
        p_email: recipientEmail,
        p_code: String(code).trim(),
      });

      if (error) {
        return new Response(
          JSON.stringify({ ok: false, error: error.message }),
          {
            status: 400,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          }
        );
      }

      return new Response(JSON.stringify(data), {
        status: 200,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    // ── Action: send (generic/default OTP dispatch) ───────────────────────────
    let token =
      payload.token ||
      payload.email_data?.token ||
      payload.code ||
      "";

    const actionType =
      payload.actionType ||
      payload.email_data?.email_action_type ||
      "signup";

    if (!token) {
      const { data: generatedCode, error: genError } = await supabase.rpc(
        "generate_account_otp",
        { p_email: recipientEmail }
      );

      if (genError) {
        console.error("Failed to generate OTP:", genError);
        return new Response(
          JSON.stringify({
            ok: false,
            error: genError.message || "Could not generate verification code.",
          }),
          {
            status: 400,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          }
        );
      }

      token = String(generatedCode).trim();
    }

    const htmlContent = buildOtpEmailHtml({
      code: token,
      actionType,
      recipientEmail,
    });

    const isRecovery = actionType === "recovery" || actionType === "reset";
    const subject = isRecovery
      ? `${token} is your Eduxfair password reset code`
      : `${token} is your Eduxfair verification code`;

    const resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: RESEND_FROM,
        to: [recipientEmail],
        subject,
        html: htmlContent,
      }),
    });

    const resendResult = await resendResponse.json();

    if (!resendResponse.ok) {
      console.error("Resend API rejected email:", resendResponse.status, resendResult);
      return new Response(
        JSON.stringify({
          ok: false,
          error: "Resend failed to deliver email",
          status: resendResponse.status,
          details: resendResult,
        }),
        {
          status: resendResponse.status,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        }
      );
    }

    return new Response(
      JSON.stringify({
        ok: true,
        message: "Verification code sent successfully via Resend",
        id: resendResult.id,
      }),
      {
        status: 200,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      }
    );
  } catch (error: any) {
    console.error("Failed in send-auth-email:", error);
    return new Response(
      JSON.stringify({
        ok: false,
        error: "Internal server error in send-auth-email",
        details: error.message,
      }),
      {
        status: 500,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      }
    );
  }
});
