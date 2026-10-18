const { test } = require('node:test');
const assert = require('node:assert/strict');
const core = require('../App/Resources/quota-core.js');

const now = 1792195200;
const orgA = '11111111-1111-4111-8111-111111111111';
const orgB = '22222222-2222-4222-8222-222222222222';

test('Claude plan comes from the selected organization, not its name or another workspace', async () => {
  const env = environment('claude', [
    { url: '/api/organizations', response: reply([
      { uuid: orgA, name: 'Personal', capabilities: ['chat', 'claude_pro'] },
      { uuid: orgB, name: 'Work', analytics_subscription_plan: 'claude_team' },
    ]) },
    { url: `/api/organizations/${orgB}/usage`, response: reply(claude) },
  ]);
  const result = await core.collect('claude', orgB, env);
  assert.equal(result.snapshot.plan, 'Team');
  assert.equal(core.claudeSelection([{ uuid: orgA, name: 'Team' }], orgA).selected.plan, '');
  env.assertDone();
});

test('Claude plan changes and unknown plans never become a hardcoded Team label', () => {
  for (const [metadata, expected] of [
    [{ capabilities: ['chat', 'claude_pro'] }, 'Pro'],
    [{ capabilities: ['chat', 'claude_max'] }, 'Max'],
    [{ analytics_subscription_plan: 'claude_enterprise' }, 'Enterprise'],
    [{ analytics_subscription_plan: 'claude_free' }, 'Free'],
    [{ plan_display_name: 'Max 20x' }, 'Max 20x'],
    [{}, ''],
  ]) {
    assert.equal(core.claudeSelection([{ uuid: orgA, name: 'Example', ...metadata }], null).selected.plan, expected);
  }
});

test('native and browser Claude collectors share selection and quota parsing', () => {
  const selection = core.claudeSelection([{ uuid: orgA, name: 'Work', capabilities: ['chat', 'claude_team'] }], null);
  const result = core.claudeUsage(claude, selection, now);
  assert.equal(result.status, 'ok');
  assert.equal(result.snapshot.plan, 'Team');
  assert.equal(result.snapshot.organizationID, orgA);
  assert.equal(result.snapshot.windows[1].usedPercent, 63.5);
  assert.equal(core.claudeSelection([{ uuid: orgA, name: 'Work' }], orgB).status, 'selectOrganization');
});
const claude = {
  five_hour: { utilization: 0, resets_at: '2026-10-17T05:00:00Z' },
  seven_day: { utilization: 63.5, resets_at: '2026-10-20T00:00:00Z' },
  seven_day_sonnet: null, seven_day_opus: null, extra_usage: null,
};
const codex = {
  plan_type: 'plus', rate_limit: {
    primary_window: { used_percent: 12, limit_window_seconds: 18000, reset_at: 1792213200 },
    secondary_window: { used_percent: 70, limit_window_seconds: 604800, reset_at: 1792454400 },
  }, credits: { has_credits: false, balance: '0', unlimited: false },
};
function reply(body, status = 200, extraHeaders = {}) {
  return { ok: status >= 200 && status < 300, status,
    headers: new Headers({ 'content-type': 'application/json', ...extraHeaders }),
    json: async () => body };
}
function environment(provider, steps) {
  let called = 0;
  return {
    origin: provider === 'claude' ? 'https://claude.ai' : 'https://chatgpt.com',
    now: () => now,
    fetch: async (url, options) => {
      const step = steps[called++];
      assert.ok(step, 'unexpected extra network request');
      assert.equal(url, step.url);
      assert.equal(options.method, 'GET');
      assert.equal(options.credentials, 'include');
      assert.equal(options.cache, 'no-store');
      assert.equal(options.redirect, 'error');
      if (step.check) step.check(options);
      return step.response;
    },
    assertDone() { assert.equal(called, steps.length); },
  };
}
test('Claude measured zero stays zero; percentages and reset instants are preserved', () => {
  const s = core.parseClaude(claude, now);
  assert.equal(s.windows.length, 2);
  assert.equal(s.windows[0].usedPercent, 0);
  assert.equal(s.windows[0].resetAt, 1792213200);
  assert.equal(s.windows[1].usedPercent, 63.5);
  assert.equal(s.fetchedAt, now);
});
test('missing Claude session is absent rather than invented as 100% remaining', () => {
  const s = core.parseClaude({ five_hour: null, seven_day: claude.seven_day }, now);
  assert.deepEqual(s.windows.map(w => w.id), ['seven_day']);
});
test('known but unreported quotas yield an explicit empty result', () => {
  assert.equal(core.parseClaude({ five_hour: null, seven_day: null }, now).windows.length, 0);
  assert.equal(core.parseCodex({ rate_limit: null, plan_type: 'pro' }, now).windows.length, 0);
});
test('unknown payloads, errors and arrays cannot masquerade as valid quota', () => {
  for (const payload of [{}, [], { error: 'unauthorized' }, null]) {
    assert.throws(() => core.parseClaude(payload, now));
    assert.throws(() => core.parseCodex(payload, now));
  }
});
test('malformed measured percentages are rejected, not coerced or clamped', () => {
  for (const value of [null, '20', NaN, Infinity, -1, 101, undefined]) {
    assert.throws(() => core.parseClaude({ five_hour: { utilization: value } }, now));
    assert.throws(() => core.parseCodex({ rate_limit: { primary_window: { used_percent: value } } }, now));
  }
});
test('invalid or missing reset time remains unknown without losing measured quota', () => {
  const s = core.parseClaude({ five_hour: { utilization: 20, resets_at: 'tomorrow' } }, now);
  assert.equal(s.windows[0].resetAt, null);
  const c = core.parseCodex({ rate_limit: { primary_window: { used_percent: 25, reset_at: -3 } } }, now);
  assert.equal(c.windows[0].resetAt, null);
  assert.equal(c.windows[0].label, '額度窗口');
});
test('Pro weekly primary is labelled weekly, never assumed to be five hours', () => {
  const s = core.parseCodex({ plan_type: 'pro', rate_limit: {
    primary_window: codex.rate_limit.secondary_window, secondary_window: null,
  } }, now);
  assert.equal(s.plan, 'pro');
  assert.equal(s.windows.length, 1);
  assert.equal(s.windows[0].label, '每週');
  assert.equal(s.windows[0].windowSeconds, 604800);
});
test('Plus has two independently measured windows and no synthetic token count', () => {
  const s = core.parseCodex(codex, now);
  assert.deepEqual(s.windows.map(w => [w.label, w.usedPercent]), [['5 小時', 12], ['每週', 70]]);
  assert.equal(s.tokenCount, undefined);
});
test('nonstandard windows retain the real duration', () => {
  const s = core.parseCodex({ rate_limit: { primary_window: {
    used_percent: 10, limit_window_seconds: 3600, reset_at: 1792213200,
  } } }, now);
  assert.equal(s.windows[0].label, '60 分鐘');
});
test('an elapsed reset never invents newly restored quota', () => {
  const s = core.parseCodex(codex, 1792999999);
  assert.equal(s.windows[0].usedPercent, 12);
  assert.equal(s.windows[0].resetAt, 1792213200);
});
test('Claude requires an explicit choice when there are two organizations', async () => {
  const env = environment('claude', [{ url: '/api/organizations', response: reply([
    { uuid: orgA, name: 'Personal' }, { uuid: orgB, name: 'My Team' },
  ]) }]);
  const result = await core.collect('claude', null, env);
  assert.equal(result.status, 'selectOrganization');
  assert.equal(result.organizations[1].id, orgB);
  assert.equal(result.snapshot, undefined);
  env.assertDone();
});
test('Claude fetches only the selected organization and never another team', async () => {
  const env = environment('claude', [
    { url: '/api/organizations', response: reply([{ uuid: orgA, name: 'Personal' }, { uuid: orgB, name: 'Team' }]) },
    { url: `/api/organizations/${orgB}/usage`, response: reply(claude) },
  ]);
  const result = await core.collect('claude', orgB, env);
  assert.equal(result.snapshot.organizationID, orgB);
  assert.equal(result.snapshot.accountLabel, 'Team');
  env.assertDone();
});
test('removed selected team does not silently switch to a remaining personal account', async () => {
  const env = environment('claude', [{ url: '/api/organizations', response: reply([{ uuid: orgA, name: 'Personal' }]) }]);
  assert.equal((await core.collect('claude', orgB, env)).status, 'selectOrganization');
  env.assertDone();
});
test('untrusted organization identifiers are not used as URL paths', async () => {
  const env = environment('claude', [{ url: '/api/organizations', response: reply([{ uuid: '../account', name: 'Bad' }]) }]);
  assert.equal((await core.collect('claude', '../account', env)).code, 'format');
  env.assertDone();
});
test('foreign origins fail before reading session or fetching usage', async () => {
  let calls = 0;
  for (const origin of ['https://claude.ai.evil.example', 'http://claude.ai', 'https://auth.openai.com']) {
    const r = await core.collect('claude', null, { origin, now: () => now, fetch: () => { calls++; } });
    assert.equal(r.code, 'login');
  }
  assert.equal(calls, 0);
});
test('Codex session token is used in headers but never returned to native code', async () => {
  const claims = Buffer.from(JSON.stringify({ 'https://api.openai.com/auth': { chatgpt_account_id: 'test-account' } })).toString('base64url');
  const token = `header.${claims}.fixture-signature`;
  const env = environment('codex', [
    { url: '/api/auth/session', response: reply({ accessToken: token, user: { email: 'private@example.test' } }) },
    { url: '/backend-api/wham/usage', response: reply(codex), check: o => {
      assert.equal(o.headers.Authorization, `Bearer ${token}`);
      assert.equal(o.headers['ChatGPT-Account-Id'], 'test-account');
    } },
  ]);
  const result = await core.collect('codex', null, env);
  assert.equal(result.status, 'ok');
  assert.ok(!JSON.stringify(result).includes(token));
  assert.ok(!JSON.stringify(result).includes('private@example.test'));
  env.assertDone();
});
test('logged-out Codex session does not proceed to quota endpoint', async () => {
  const env = environment('codex', [{ url: '/api/auth/session', response: reply({}) }]);
  assert.equal((await core.collect('codex', null, env)).code, 'login');
  env.assertDone();
});
test('401 clears auth, 403 remains a distinct permission error', async () => {
  for (const [status, code] of [[401, 'login'], [403, 'forbidden'], [503, 'server']]) {
    const env = environment('claude', [{ url: '/api/organizations', response: reply({ token: 'DO_NOT_LEAK' }, status) }]);
    const result = await core.collect('claude', null, env);
    assert.equal(result.code, code);
    assert.ok(!JSON.stringify(result).includes('DO_NOT_LEAK'));
  }
});
test('429 honours Retry-After rather than rapid polling', async () => {
  for (const [header, expected] of [['125', 125], ['invalid', 60], [new Date((now + 90) * 1000).toUTCString(), 90]]) {
    const env = environment('claude', [{ url: '/api/organizations', response: reply({}, 429, { 'retry-after': header }) }]);
    const result = await core.collect('claude', null, env);
    assert.equal(result.code, 'rateLimited');
    assert.equal(result.retryAfter, expected);
  }
});
test('HTML challenge is never decoded as quota or exposed in an error message', async () => {
  const env = environment('claude', [{ url: '/api/organizations', response: reply('secret HTML', 403, { 'content-type': 'text/html' }) }]);
  const result = await core.collect('claude', null, env);
  assert.equal(result.code, 'challenge');
  assert.ok(!JSON.stringify(result).includes('secret'));
});
test('network errors are sanitized and have no new successful snapshot', async () => {
  const result = await core.collect('claude', null, {
    origin: 'https://claude.ai', now: () => now,
    fetch: async () => { throw new Error('Bearer SECRET in external error'); },
  });
  assert.equal(result.code, 'network');
  assert.equal(result.snapshot, undefined);
  assert.ok(!JSON.stringify(result).includes('SECRET'));
});
