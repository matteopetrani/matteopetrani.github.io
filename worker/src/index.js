const CORS_ORIGIN = 'https://matteopetrani.com';

// ── HMAC helpers ─────────────────────────────────────────────────────────────

async function hmacSign(secret, message) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(message));
  return btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

async function hmacVerify(secret, message, token) {
  const expected = await hmacSign(secret, message);
  return expected === token;
}

function makeToken(email, lang, expiry) {
  // payload: email|lang|expiry  (expiry = 0 for unsubscribe = no expiry)
  return btoa(`${email}|${lang}|${expiry}`)
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

function parseToken(raw) {
  try {
    const padded = raw.replace(/-/g, '+').replace(/_/g, '/');
    const decoded = atob(padded);
    const [email, lang, expiry] = decoded.split('|');
    return { email, lang, expiry: Number(expiry) };
  } catch {
    return null;
  }
}

async function buildSignedToken(env, email, lang, expiryMs) {
  const expiry = expiryMs === 0 ? 0 : Date.now() + expiryMs;
  const payload = makeToken(email, lang, expiry);
  const sig = await hmacSign(env.HMAC_SECRET, payload);
  return `${payload}.${sig}`;
}

async function verifySignedToken(env, token) {
  const dot = token.lastIndexOf('.');
  if (dot === -1) return null;
  const payload = token.slice(0, dot);
  const sig = token.slice(dot + 1);
  const valid = await hmacVerify(env.HMAC_SECRET, payload, sig);
  if (!valid) return null;
  const data = parseToken(payload);
  if (!data) return null;
  if (data.expiry !== 0 && Date.now() > data.expiry) return null;
  return data;
}

// ── Resend API helpers ────────────────────────────────────────────────────────

function audienceId(env, lang) {
  return lang === 'en' ? env.RESEND_SEGMENT_ID_EN : env.RESEND_SEGMENT_ID_IT;
}

async function resendRequest(env, method, path, body) {
  const res = await fetch(`https://api.resend.com${path}`, {
    method,
    headers: {
      'Authorization': `Bearer ${env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  return res;
}

async function findContact(env, audienceId, email) {
  const res = await resendRequest(env, 'GET', `/audiences/${audienceId}/contacts`);
  if (!res.ok) return null;
  const data = await res.json();
  return (data.data || []).find(c => c.email === email) || null;
}

// ── Email templates ───────────────────────────────────────────────────────────

function confirmationEmail(lang, confirmUrl) {
  const it = lang === 'it';
  return {
    subject: it ? 'Conferma iscrizione — Matteo Petrani' : 'Confirm subscription — Matteo Petrani',
    html: `<!DOCTYPE html><html><body style="font-family:monospace;max-width:560px;margin:40px auto;color:#23282e;background:#f6f8fa;padding:32px">
<h2 style="font-weight:400;margin-bottom:16px">${it ? 'Conferma la tua iscrizione' : 'Confirm your subscription'}</h2>
<p>${it ? 'Clicca il link qui sotto per completare l\'iscrizione alla newsletter di Matteo Petrani.' : 'Click the link below to complete your subscription to Matteo Petrani\'s newsletter.'}</p>
<p><a href="${confirmUrl}" style="color:#0553b3">${it ? 'Conferma iscrizione →' : 'Confirm subscription →'}</a></p>
<p style="color:#717a84;font-size:0.85em">${it ? 'Se non hai richiesto questa iscrizione, ignora questa email.' : 'If you didn\'t request this, just ignore this email.'}</p>
</body></html>`,
  };
}

// ── CORS helpers ──────────────────────────────────────────────────────────────

function corsHeaders(origin) {
  const allowed = origin === CORS_ORIGIN || origin === 'http://localhost:4000';
  return {
    'Access-Control-Allow-Origin': allowed ? origin : CORS_ORIGIN,
    'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };
}

function json(data, status = 200, origin = CORS_ORIGIN) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders(origin) },
  });
}

// ── Handlers ──────────────────────────────────────────────────────────────────

async function handleSubscribe(request, env) {
  const origin = request.headers.get('Origin') || '';
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400, origin);
  }

  const { email, lang } = body;
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return json({ error: 'Invalid email' }, 400, origin);
  }
  if (lang !== 'it' && lang !== 'en') {
    return json({ error: 'Invalid lang' }, 400, origin);
  }

  const aid = audienceId(env, lang);

  // Check if already subscribed
  const existing = await findContact(env, aid, email);
  if (existing && !existing.unsubscribed) {
    // Already confirmed — silently succeed (don't leak info)
    return json({ ok: true }, 200, origin);
  }

  // Create or re-add contact (unsubscribed = true until confirmed)
  await resendRequest(env, 'POST', `/audiences/${aid}/contacts`, {
    email,
    unsubscribed: true,
  });

  // Generate confirmation token (24h expiry)
  const token = await buildSignedToken(env, email, lang, 24 * 60 * 60 * 1000);
  const workerBase = env.WORKER_BASE_URL.replace(/\/$/, '');
  const confirmUrl = `${workerBase}/confirm?token=${encodeURIComponent(token)}`;

  // Send confirmation email
  const tpl = confirmationEmail(lang, confirmUrl);
  await resendRequest(env, 'POST', '/emails', {
    from: `Matteo Petrani <newsletter@matteopetrani.com>`,
    to: [email],
    subject: tpl.subject,
    html: tpl.html,
  });

  return json({ ok: true }, 200, origin);
}

async function handleConfirm(request, env) {
  const url = new URL(request.url);
  const token = url.searchParams.get('token');
  if (!token) return new Response('Invalid link.', { status: 400 });

  const data = await verifySignedToken(env, token);
  if (!data) return new Response('Link expired or invalid.', { status: 400 });

  const { email, lang } = data;
  const aid = audienceId(env, lang);

  // Mark as subscribed
  const contact = await findContact(env, aid, email);
  if (contact) {
    await resendRequest(env, 'PATCH', `/audiences/${aid}/contacts/${contact.id}`, {
      unsubscribed: false,
    });
  }

  const siteBase = lang === 'en' ? 'https://matteopetrani.com/en/' : 'https://matteopetrani.com/it/';
  return Response.redirect(`${siteBase}?subscribed=1`, 302);
}

async function handleUnsubscribe(request, env) {
  const url = new URL(request.url);
  const token = url.searchParams.get('token');
  if (!token) return new Response('Invalid link.', { status: 400 });

  const data = await verifySignedToken(env, token);
  if (!data) return new Response('Invalid unsubscribe link.', { status: 400 });

  const { email, lang } = data;

  // Remove from both audiences (in case lang was wrong or changed)
  for (const aid of [env.RESEND_SEGMENT_ID_IT, env.RESEND_SEGMENT_ID_EN]) {
    const contact = await findContact(env, aid, email);
    if (contact) {
      await resendRequest(env, 'DELETE', `/audiences/${aid}/contacts/${contact.id}`);
    }
  }

  const it = lang === 'it';
  return new Response(
    `<!DOCTYPE html><html><body style="font-family:monospace;max-width:560px;margin:40px auto;color:#23282e;padding:32px">
    <p>${it ? 'Sei stato disiscritto dalla newsletter.' : 'You have been unsubscribed from the newsletter.'}</p>
    <p><a href="https://matteopetrani.com/${lang}/" style="color:#0553b3">${it ? '← Torna al sito' : '← Back to the site'}</a></p>
    </body></html>`,
    { status: 200, headers: { 'Content-Type': 'text/html' } }
  );
}

// ── Main fetch handler ────────────────────────────────────────────────────────

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get('Origin') || '';

    // CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders(origin) });
    }

    if (request.method === 'POST' && url.pathname === '/subscribe') {
      return handleSubscribe(request, env);
    }
    if (request.method === 'GET' && url.pathname === '/confirm') {
      return handleConfirm(request, env);
    }
    if (request.method === 'GET' && url.pathname === '/unsubscribe') {
      return handleUnsubscribe(request, env);
    }

    return new Response('Not found', { status: 404 });
  },
};
