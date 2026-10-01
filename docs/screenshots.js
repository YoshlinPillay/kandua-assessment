// Capture documentation screenshots with the stack's own headless browser (browserless, used by Lightdash).
// Runs inside a container on the compose network: `make screenshots` (docs/images/*.png).
// Prints {name: base64png} JSON on stdout; the Makefile target decodes it.
const BROWSER = process.env.BROWSER_URL || 'http://headless-browser:3000';

const shots = {
  // Dagster: global asset lineage, raw JSON (dlt) -> staging -> core -> marts (dbt)
  'dagster-lineage': `export default async ({ page }) => {
    await page.setViewport({ width: 1700, height: 950 });
    await page.goto('http://dagster-webserver:3000/asset-groups', { waitUntil: 'networkidle2', timeout: 60000 });
    await new Promise((r) => setTimeout(r, 6000));
    return { data: await page.screenshot({ encoding: 'base64' }), type: 'application/json' };
  }`,
  // Chat: a real question answered from Cube, with the queries expander open
  'chat-answer': `export default async ({ page }) => {
    await page.setViewport({ width: 1280, height: 1000 });
    await page.goto('${process.env.CHAT_URL}', { waitUntil: 'networkidle2', timeout: 60000 });
    const box = 'textarea[data-testid="stChatInputTextArea"]';
    await page.waitForSelector(box, { timeout: 60000 });
    await page.type(box, 'Which bar does Juan visit the most, and by how much?');
    await page.keyboard.press('Enter');
    await page.waitForFunction(() => document.body.innerText.includes('Queries ('), { timeout: 120000 });
    await new Promise((r) => setTimeout(r, 1500));
    return { data: await page.screenshot({ encoding: 'base64' }), type: 'application/json' };
  }`,
  // Chat: the topic guardrail (off-topic question -> meme GIF, no data queried)
  'chat-off-topic': `export default async ({ page }) => {
    await page.setViewport({ width: 1280, height: 900 });
    await page.goto('${process.env.CHAT_URL}', { waitUntil: 'networkidle2', timeout: 60000 });
    const box = 'textarea[data-testid="stChatInputTextArea"]';
    await page.waitForSelector(box, { timeout: 60000 });
    await page.type(box, 'What is the capital of France?');
    await page.keyboard.press('Enter');
    await page.waitForFunction(() => document.querySelectorAll('[data-testid="stImage"] img').length > 0,
      { timeout: 120000 });
    await new Promise((r) => setTimeout(r, 1500));
    return { data: await page.screenshot({ encoding: 'base64' }), type: 'application/json' };
  }`,
};

(async () => {
  const out = {};
  for (const [name, code] of Object.entries(shots)) {
    const res = await fetch(`${BROWSER}/function?timeout=180000`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code }),
    });
    const body = await res.json().catch(async () => ({ error: await res.text() }));
    if (!res.ok || !body.data) {
      console.error(`${name}: failed ${res.status} ${JSON.stringify(body).slice(0, 300)}`);
      continue;
    }
    out[name] = body.data;
    console.error(`${name}: ok`);
  }
  process.stdout.write(JSON.stringify(out));
})();
