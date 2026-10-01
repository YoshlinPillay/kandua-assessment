# Dagster webserver/daemon image with dlt + dbt baked in. Build context: repo root.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 DAGSTER_HOME=/opt/dagster/home
WORKDIR /app

COPY requirements.lock pyproject.toml ./
RUN pip install --no-cache-dir -r requirements.lock

COPY ingestion ./ingestion
COPY orchestration ./orchestration
COPY transform ./transform
COPY chat ./chat
RUN pip install --no-cache-dir --no-deps -e . \
 && mkdir -p "$DAGSTER_HOME" && cp orchestration/dagster.yaml "$DAGSTER_HOME/dagster.yaml" \
 # Parse the dbt manifest at build time (no DB needed) so Dagster can load the asset graph on start.
 && cd transform && dbt deps --profiles-dir . && dbt parse --profiles-dir .

EXPOSE 3000
CMD ["dagster-webserver", "-h", "0.0.0.0", "-p", "3000", "-m", "orchestration.definitions"]
