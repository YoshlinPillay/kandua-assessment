// Export the "Juan the Drinker" dashboard as a PNG via Lightdash's own export (headless browser) and save it to
// /app/lightdash/_dashboard.png (moved to docs/images by `make screenshot`). Runs inside the lightdash-cli container.
const fs = require('fs');

const H = { Authorization: `ApiKey ${process.env.LIGHTDASH_API_KEY}`, 'Content-Type': 'application/json' };
const U = process.env.LIGHTDASH_URL; // internal URL: containers can't reach the host's LAN IP
const get = async (path) => (await (await fetch(U + path, { headers: H })).json()).results;

(async () => {
  const project = (await get('/api/v1/org/projects')).find((p) => p.name === 'Juan the Drinker');
  const dashboard = (await get(`/api/v1/projects/${project.projectUuid}/dashboards`)).find(
    (d) => d.name === 'Juan the Drinker',
  );
  const exported = await fetch(`${U}/api/v1/dashboards/${dashboard.uuid}/export`, {
    method: 'POST',
    headers: H,
    body: JSON.stringify({ queryFilters: '', gridWidth: 1400 }),
  });
  const imageUrl = (await exported.json()).results; // public SITE_URL link -> rewrite to the internal host
  const image = await fetch(imageUrl.replace(/^https?:\/\/[^/]+/, U), { headers: H });
  if (!image.ok) throw new Error(`download failed: ${image.status}`);
  fs.writeFileSync('/app/lightdash/_dashboard.png', Buffer.from(await image.arrayBuffer()));
  console.log('dashboard exported');
})();
