#!/bin/sh
# Idempotent Lightdash deploy: update the "Juan the Drinker" project if it exists, otherwise create it.
# Only the star schema (marts) is exposed as explores; staging/core stay internal (the BI role can't read staging).
set -eu
PROJECT_NAME="Juan the Drinker"

uuid=$(node -e '
  fetch(process.env.LIGHTDASH_URL + "/api/v1/org/projects", { headers: { Authorization: "ApiKey " + process.env.LIGHTDASH_API_KEY } })
    .then(r => r.json())
    .then(j => { const p = (j.results || []).find(p => p.name === process.argv[1]); console.log(p ? p.projectUuid : ""); })
' "$PROJECT_NAME")

if [ -n "$uuid" ]; then
  echo "Updating existing Lightdash project $uuid"
  LIGHTDASH_PROJECT="$uuid" lightdash deploy --select marts --assume-yes --target reader --profiles-dir . --project-dir .
else
  echo "Creating Lightdash project"
  lightdash deploy --create "$PROJECT_NAME" --select marts --assume-yes --target reader --profiles-dir . --project-dir .
fi

# Content as code: charts + dashboard from lightdash/. Lint against the official schemas first (guardrail).
uuid=$(node -e '
  fetch(process.env.LIGHTDASH_URL + "/api/v1/org/projects", { headers: { Authorization: "ApiKey " + process.env.LIGHTDASH_API_KEY } })
    .then(r => r.json()).then(j => console.log((j.results || []).find(p => p.name === process.argv[1]).projectUuid));
' "$PROJECT_NAME")
lightdash lint --path /app/lightdash
lightdash upload --project "$uuid" --path /app/lightdash --force
