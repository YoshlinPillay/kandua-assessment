# Lightdash CLI (pinned to the server version) + dbt, used to deploy the dbt project to Lightdash from code.
FROM node:24-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-venv \
 && rm -rf /var/lib/apt/lists/* \
 && python3 -m venv /opt/dbt \
 && /opt/dbt/bin/pip install --no-cache-dir "dbt-core==1.12.5" "dbt-postgres==1.11.0" \
 && npm install -g @lightdash/cli@2.399.4

ENV PATH="/opt/dbt/bin:${PATH}"
WORKDIR /app/transform
ENTRYPOINT ["lightdash"]
