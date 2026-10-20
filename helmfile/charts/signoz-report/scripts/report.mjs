import { readFileSync } from 'node:fs';
import { chromium } from 'playwright';

const env = (name) => {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
};
const secret = (envName) => readFileSync(`/mnt/secrets-store/${env(envName)}`, 'utf8').trim();

const signozUrl = env('SIGNOZ_URL').replace(/\/$/, '');
const publicUrl = env('SIGNOZ_PUBLIC_URL').replace(/\/$/, '');
const dashboards = JSON.parse(env('REPORT_DASHBOARDS'));
const recipients = JSON.parse(env('REPORT_RECIPIENTS'));
const defaultRange = env('REPORT_DEFAULT_RELATIVE_TIME');
const viewport = {
  width: Number(env('REPORT_VIEWPORT_WIDTH')),
  height: Number(env('REPORT_VIEWPORT_HEIGHT')),
};
const settleMs = Number(env('REPORT_SETTLE_SECONDS')) * 1000;
const notifyUrl = env('NOTIFY_API_URL').replace(/\/$/, '');
const templateId = env('NOTIFY_TEMPLATE_ID');

if (dashboards.length === 0) throw new Error('No dashboards configured');
if (recipients.length === 0) throw new Error('No recipients configured');

async function login(page) {
  await page.goto(`${signozUrl}/login`, { waitUntil: 'networkidle' });
  await page.locator('input[type="email"], input[name="email"], #loginEmail').first().fill(secret('SECRET_SIGNOZ_EMAIL'));
  const password = page.locator('input[type="password"]').first();
  if (!(await password.isVisible())) {
    await page.getByRole('button', { name: /next/i }).click();
  }
  await password.fill(secret('SECRET_SIGNOZ_PASSWORD'));
  await page.keyboard.press('Enter');
  await page.waitForURL((url) => !url.pathname.startsWith('/login'), { timeout: 30000 });
}

// Crops to the bottom of the last panel; grows the viewport first if panels overflow it
async function screenshotContent(page) {
  const padding = 16;
  const measure = () =>
    page.evaluate(() => Math.max(0, ...[...document.querySelectorAll('.react-grid-item')].map((el) => el.getBoundingClientRect().bottom)));

  let bottom = await measure();
  if (bottom === 0) return page.screenshot();

  if (bottom + padding > viewport.height) {
    await page.setViewportSize({ width: viewport.width, height: Math.ceil(bottom + padding) });
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(settleMs);
    bottom = await measure();
  }
  return page.screenshot({ clip: { x: 0, y: 0, width: viewport.width, height: Math.ceil(bottom + padding) } });
}

const browser = await chromium.launch({ args: ['--no-sandbox'] });
// Container locale is unset, which makes the SigNoz UI crash in Intl.NumberFormat
const context = await browser.newContext({ viewport, locale: 'en-US', ignoreHTTPSErrors: process.env.SIGNOZ_IGNORE_TLS_ERRORS === 'true' });
const page = await context.newPage();
page.on('pageerror', (err) => console.error('[pageerror]', err.stack ?? err.message));
page.on('console', (msg) => msg.type() === 'error' && console.error('[console]', msg.text()));
page.on('response', (res) => res.status() >= 400 && console.error(`[http ${res.status()}]`, res.request().method(), res.url()));
const personalisation = {};
const links = [];
const failures = [];

try {
  await login(page);

  for (const [index, dashboard] of dashboards.entries()) {
    const range = dashboard.relativeTime ?? defaultRange;
    const query = new URLSearchParams({ relativeTime: range });
    if (dashboard.variables) query.set('variables', JSON.stringify(dashboard.variables));
    try {
      await page.goto(`${signozUrl}/dashboard/${dashboard.id}?${query}`, { waitUntil: 'networkidle' });
      await page.waitForTimeout(settleMs);
      const png = await screenshotContent(page);
      personalisation[`dashboard_${index + 1}`] = {
        file: png.toString('base64'),
        filename: `${dashboard.title.replace(/[^\w.-]+/g, '_')}.png`,
        sending_method: 'attach',
      };
      links.push(`- [${dashboard.title}](${publicUrl}/dashboard/${dashboard.id}?${query}) (last ${range})`);
    } catch (err) {
      console.error(`Failed to capture ${dashboard.title}:`, err);
      failures.push(dashboard.title);
    }
  }
} finally {
  await browser.close();
}

if (failures.length > 0) {
  links.push(`- Failed to capture: ${failures.join(', ')}`);
}
// Optional ((report_links)) placeholder in the template
personalisation.report_links = links.join('\n');

if (Object.keys(personalisation).length > 1) {
  const apiKey = secret('SECRET_NOTIFY_API_KEY');
  for (const emailAddress of recipients) {
    const res = await fetch(`${notifyUrl}/v2/notifications/email`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `ApiKey-v1 ${apiKey}` },
      body: JSON.stringify({ email_address: emailAddress, template_id: templateId, personalisation }),
    });
    if (!res.ok) throw new Error(`Notify returned ${res.status} for ${emailAddress}: ${await res.text()}`);
  }
}

if (failures.length > 0) process.exit(1);
