/**
 * Called by a Supabase Database Webhook on public.users UPDATE.
 * When is_active goes false → true for a staff role, emails them their skf_official_id.
 *
 * Secrets (Dashboard → Edge Functions → send-staff-activated → Secrets):
 *   RESEND_API_KEY   — from https://resend.com/api-keys
 *   RESEND_FROM      — e.g. "Saudi Karate Federation <onboarding@resend.dev>" or your verified domain
 *   INTERNAL_HOOK_SECRET — optional; set same value as custom header x-hook-secret on the webhook
 *   REPLY_TO_EMAIL   — optional; replies from the recipient go here (your support inbox)
 *   EMAIL_HEADER_URL — SKF banner: full https URL to SKF2.jpeg (must be publicly reachable)
 *   EMAIL_LOGO_URL   — optional; small extra logo below header if you still want it
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

/** Webhooks / JSON sometimes send booleans as strings; normalize. */
function rowIsActive(v: unknown): boolean {
  if (v === true || v === 1) return true;
  if (typeof v === "string") {
    const s = v.toLowerCase();
    return s === "true" || s === "t" || s === "1" || s === "yes";
  }
  return false;
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-hook-secret",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  const hookSecret = Deno.env.get("INTERNAL_HOOK_SECRET");
  if (hookSecret) {
    const h = req.headers.get("x-hook-secret");
    if (h !== hookSecret) {
      return new Response(JSON.stringify({ error: "unauthorized" }), {
        status: 401,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }
  }

  let payload: {
    type?: string;
    table?: string;
    record?: Record<string, unknown>;
    old_record?: Record<string, unknown>;
  };
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid json" }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const rec = payload.record;
  const old = payload.old_record;
  const table = String(payload.table || "");
  if (!rec || (!table.endsWith("users") && table !== "users")) {
    console.log("send-staff-activated skip:", { table, hasRecord: !!rec });
    return new Response(JSON.stringify({ skipped: true, reason: "not_users_table", table }), {
      status: 200,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const wasInactive = !old || !rowIsActive(old.is_active);
  const nowActive = rowIsActive(rec.is_active);
  const skfId = String(rec.skf_official_id ?? "").trim();
  const role = String(rec.role || "").toLowerCase();
  const staff = role === "skf_admin" || role === "admin" || role === "referees_plus";
  const email = typeof rec.email === "string" ? rec.email.trim().toLowerCase() : "";

  if (!wasInactive || !nowActive || !skfId || !staff || !email.includes("@")) {
    const reason = {
      skipped: true,
      wasInactive,
      nowActive,
      hasSkfId: !!skfId,
      staff,
      hasEmail: email.includes("@"),
    };
    console.log("send-staff-activated skip conditions:", reason);
    return new Response(JSON.stringify(reason), {
      status: 200,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const apiKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("RESEND_FROM") || "SKF <onboarding@resend.dev>";
  if (!apiKey) {
    console.error("Missing RESEND_API_KEY");
    return new Response(JSON.stringify({ error: "RESEND_API_KEY not configured" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const subject =
    role === "referees_plus"
      ? "Your SKF Referees+ access is active"
      : "Your SKF administrator ID";

  const headerUrl = (Deno.env.get("EMAIL_HEADER_URL") || "").trim();
  const headerRow = headerUrl.startsWith("https://")
    ? `<tr><td style="padding:0;line-height:0;background:#0d3d2a;"><img src="${escapeHtml(headerUrl)}" width="560" alt="Saudi Karate Federation" style="display:block;width:100%;max-width:560px;height:auto;border:0;" /></td></tr>`
    : "";

  const titleBar = headerRow
    ? ""
    : `<tr><td style="background:#1a237e;color:#fff;padding:20px 24px;font-size:18px;font-weight:600;">Saudi Karate Federation</td></tr>`;

  const logoUrl = (Deno.env.get("EMAIL_LOGO_URL") || "").trim();
  const logoBlock =
    logoUrl.startsWith("https://") && !headerRow
      ? `<div style="text-align:center;margin-bottom:20px;"><img src="${escapeHtml(logoUrl)}" alt="" style="max-width:200px;height:auto;" /></div>`
      : logoUrl.startsWith("https://")
      ? `<div style="text-align:center;margin:16px 0;"><img src="${escapeHtml(logoUrl)}" alt="" style="max-width:160px;height:auto;" /></div>`
      : "";

  const html = `
<!DOCTYPE html><html><body style="margin:0;padding:24px;background:#f5f5f5;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;margin:0 auto;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">
    ${headerRow}
    ${titleBar}
    <tr><td style="padding:28px 24px;color:#333;line-height:1.5;">
      ${logoBlock}
      <p style="margin:0 0 12px;">Hello,</p>
      <p style="margin:0 0 12px;">Your federation account is now <strong>active</strong>.</p>
      <p style="margin:0 0 8px;">Your SKF official ID:</p>
      <p style="margin:0 0 20px;font-size:22px;letter-spacing:3px;font-weight:700;color:#1b5e20;">${escapeHtml(skfId)}</p>
      <p style="margin:0 0 16px;font-size:14px;color:#555;">Use this ID (or your email) to sign in on the SKF admin login page where applicable.</p>
      <p style="margin:0;font-size:13px;color:#888;">— Saudi Karate Federation (SKF)</p>
    </td></tr>
  </table>
</body></html>`;

  const replyTo = (Deno.env.get("REPLY_TO_EMAIL") || "").trim();
  const emailPayload: Record<string, unknown> = {
    from,
    to: [email],
    subject,
    html,
  };
  if (replyTo.includes("@")) {
    emailPayload.reply_to = replyTo;
  }

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(emailPayload),
  });

  const text = await res.text();
  if (!res.ok) {
    console.error("Resend error", res.status, text);
    return new Response(JSON.stringify({ error: "resend failed", detail: text }), {
      status: 502,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { ...cors, "Content-Type": "application/json" },
  });
});

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
