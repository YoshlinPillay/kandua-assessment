// Make the dashboard's space visible to everyone in the project (admins manage, viewers read).
// `lightdash upload` creates spaces as private to the uploading user (the deploy bot), so reviewers and the
// human admin couldn't see or move the dashboard. Idempotent: only private spaces we manage are changed.
const H = { Authorization: `ApiKey ${process.env.LIGHTDASH_API_KEY}`, 'Content-Type': 'application/json' };
const U = process.env.LIGHTDASH_URL;
const MANAGED = ['Juan the drinker']; // spaceSlug juan-the-drinker in lightdash/charts + dashboards

async function api(method, path, body) {
  const res = await fetch(U + path, { method, headers: H, body: body && JSON.stringify(body) });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status} ${JSON.stringify(json).slice(0, 200)}`);
  return json.results;
}

(async () => {
  const project = (await api('GET', '/api/v1/org/projects')).find((p) => p.name === 'Juan the Drinker');
  const spaces = await api('GET', `/api/v1/projects/${project.projectUuid}/spaces`);
  for (const space of spaces.filter((s) => MANAGED.includes(s.name))) {
    if (space.inheritsFromOrgOrProject) {
      console.log(`space "${space.name}": already visible to the project`);
      continue;
    }
    await api('PATCH', `/api/v1/projects/${project.projectUuid}/spaces/${space.uuid}`, {
      name: space.name,
      inheritParentPermissions: true,
    });
    console.log(`space "${space.name}": now visible to all project members`);
  }
})().catch((e) => {
  console.error(`publish-spaces failed: ${e.message}`);
  process.exit(1);
});
