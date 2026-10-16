(function (root) {
  'use strict';
  class Failure extends Error {
    constructor(code, retryAfter = 0) { super(code); this.code = code; this.retryAfter = retryAfter; }
  }
  const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
  const has = (obj, key) => Object.prototype.hasOwnProperty.call(obj, key);
  const clean = value => typeof value === 'string' ? value.replace(/[\u0000-\u001f\u007f]/g, '').slice(0, 80) : '';
  const seconds = value => typeof value === 'number' && Number.isFinite(value) && value > 0 && value < 253402300800 ? value : null;
  function percentage(value) {
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 100) throw new Failure('format');
    return value;
  }
  function snapshot(provider, windows, timestamp, plan = '') {
    return { provider, windows, fetchedAt: timestamp, plan, organizationID: null, accountLabel: '' };
  }
  function parseClaude(payload, timestamp) {
    const definitions = [
      ['five_hour', '5 小時', 18000], ['seven_day', '每週', 604800],
      ['seven_day_opus', 'Opus 每週', 604800], ['seven_day_sonnet', 'Sonnet 每週', 604800],
    ];
    if (!object(payload) || !definitions.some(([key]) => has(payload, key))) throw new Failure('format');
    const windows = [];
    for (const [id, label, duration] of definitions) {
      const window = payload[id];
      if (window === null || window === undefined) continue;
      if (!object(window)) throw new Failure('format');
      // Require a timezone-bearing ISO timestamp; a locale date is not an instant.
      const iso = window.resets_at;
      const resetAt = typeof iso === 'string' && /^\d{4}-\d\d-\d\dT.*(?:Z|[+-]\d\d:\d\d)$/.test(iso)
        ? seconds(Date.parse(iso) / 1000) : null;
      windows.push({ id, label, usedPercent: percentage(window.utilization), resetAt, windowSeconds: duration });
    }
    return snapshot('claude', windows, timestamp);
  }
  function parseCodex(payload, timestamp) {
    if (!object(payload) || !has(payload, 'rate_limit')) throw new Failure('format');
    const windows = [];
    if (payload.rate_limit !== null) {
      const limit = payload.rate_limit;
      if (!object(limit) || !['primary_window', 'secondary_window'].some(key => has(limit, key))) throw new Failure('format');
      for (const id of ['primary_window', 'secondary_window']) {
        const window = limit[id];
        if (window === null || window === undefined) continue;
        if (!object(window)) throw new Failure('format');
        const duration = Number.isInteger(window.limit_window_seconds) && window.limit_window_seconds > 0
          ? window.limit_window_seconds : null;
        const label = duration === 18000 ? '5 小時' : duration === 604800 ? '每週'
          : duration !== null ? `${Math.round(duration / 60)} 分鐘` : '額度窗口';
        windows.push({ id, label, usedPercent: percentage(window.used_percent),
          resetAt: seconds(window.reset_at), windowSeconds: duration });
      }
    }
    return snapshot('codex', windows, timestamp, clean(payload.plan_type));
  }
  function retrySeconds(header, now) {
    const numeric = header !== null && /^\d+(\.\d+)?$/.test(header.trim()) ? Number(header) : NaN;
    const value = Number.isFinite(numeric) ? numeric : (Date.parse(header) / 1000 - now);
    return Number.isFinite(value) && value > 0 ? Math.max(1, Math.ceil(value)) : 60;
  }
  async function request(env, path, headers = {}) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    try {
      const response = await env.fetch(path, {
        method: 'GET', credentials: 'include', cache: 'no-store', redirect: 'error',
        headers: { Accept: 'application/json', ...headers }, signal: controller.signal,
      });
      const isJSON = (response.headers.get('content-type') || '').includes('application/json');
      if (response.status === 401) throw new Failure('login');
      if (response.status === 429) throw new Failure('rateLimited', retrySeconds(response.headers.get('retry-after'), env.now()));
      if (response.status === 403) throw new Failure(isJSON ? 'forbidden' : 'challenge');
      if (response.status >= 500) throw new Failure('server');
      if (!response.ok) throw new Failure('format');
      if (!isJSON) throw new Failure('challenge');
      try { return await response.json(); } catch (_) { throw new Failure('format'); }
    } finally { clearTimeout(timeout); }
  }
  function accountID(token) {
    // Decode routing metadata only; this is not token verification or authorization.
    try {
      let base64 = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
      base64 += '='.repeat((4 - base64.length % 4) % 4);
      const claims = JSON.parse(atob(base64));
      const id = claims['https://api.openai.com/auth']?.chatgpt_account_id;
      return typeof id === 'string' && /^[a-zA-Z0-9_-]{1,128}$/.test(id) ? id : null;
    } catch (_) { return null; }
  }
  async function collect(provider, organizationID, environment) {
    const env = environment || { origin: location.origin, now: () => Date.now() / 1000, fetch: fetch.bind(root) };
    try {
      const expected = provider === 'claude' ? 'https://claude.ai' : provider === 'codex' ? 'https://chatgpt.com' : null;
      if (!expected || env.origin !== expected) throw new Failure('login');
      if (provider === 'claude') {
        const raw = await request(env, '/api/organizations');
        if (!Array.isArray(raw)) throw new Failure('format');
        const organizations = raw.map(org => {
          if (!object(org) || typeof org.uuid !== 'string' || !/^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$/.test(org.uuid)) {
            throw new Failure('format');
          }
          return { id: org.uuid, name: clean(org.name) || '未命名空間' };
        });
        if (organizations.length === 0) throw new Failure('forbidden');
        const selected = organizations.find(org => org.id === organizationID)
          || (!organizationID && organizations.length === 1 ? organizations[0] : null);
        if (!selected) return { status: 'selectOrganization', organizations };
        const data = await request(env, `/api/organizations/${selected.id}/usage`);
        const result = parseClaude(data, env.now());
        result.organizationID = selected.id;
        result.accountLabel = selected.name;
        return { status: 'ok', snapshot: result, organizations };
      }
      const session = await request(env, '/api/auth/session');
      if (!object(session) || typeof session.accessToken !== 'string' || !session.accessToken) throw new Failure('login');
      const headers = { Authorization: `Bearer ${session.accessToken}` };
      const id = accountID(session.accessToken);
      if (id) headers['ChatGPT-Account-Id'] = id;
      const data = await request(env, '/backend-api/wham/usage', headers);
      return { status: 'ok', snapshot: parseCodex(data, env.now()) };
    } catch (error) {
      return { status: 'error', code: error instanceof Failure ? error.code : 'network',
        retryAfter: error instanceof Failure ? error.retryAfter : 0 };
    }
  }
  const core = { parseClaude, parseCodex, collect };
  root.QuotaCore = core;
  if (typeof module !== 'undefined') module.exports = core;
})(globalThis);
