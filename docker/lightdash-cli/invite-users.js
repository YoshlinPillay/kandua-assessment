// Create Lightdash invite links on a headless deployment (no SMTP): an admin login for the human and a viewer
// login for the reviewers. Prints the links to stdout; deploy.sh stores them root-only on the host.
// Idempotent: users that already exist are skipped. Usage: node invite-users.js <admin-email>
const H = { Authorization: `ApiKey ${process.env.LIGHTDASH_API_KEY}`, 'Content-Type': 'application/json' };
const U = process.env.LIGHTDASH_URL;
const PUBLIC = process.env.LIGHTDASH_SITE_URL || U;
const WEEK = 7 * 24 * 3600 * 1000;

const users = [
  { email: process.argv[2], role: 'admin', label: 'Admin (you)' },
  { email: 'reviewer@kandua-assessment.example', role: 'viewer', label: 'Reviewers (read-only)' },
];

(async () => {
  const existing = await (await fetch(`${U}/api/v1/org/users`, { headers: H })).json();
  const emails = new Set((existing.results?.data || existing.results || []).map((u) => u.email));
  for (const { email, role, label } of users) {
    if (!email || emails.has(email)) {
      console.log(`${label}: ${email} already exists, skipped`);
      continue;
    }
    const res = await fetch(`${U}/api/v1/invite-links`, {
      method: 'POST',
      headers: H,
      body: JSON.stringify({ email, role, expiresAt: new Date(Date.now() + WEEK).toISOString() }),
    });
    const body = await res.json();
    if (!res.ok) throw new Error(`invite for ${email} failed: ${res.status} ${JSON.stringify(body)}`);
    const url = body.results.inviteUrl.replace(/^https?:\/\/[^/]+/, PUBLIC);
    console.log(`${label}: ${email} -> ${url}`);
  }
})();
