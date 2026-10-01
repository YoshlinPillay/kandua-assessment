#!/bin/sh
# Start MinIO, create the bucket Lightdash writes query results to, then keep the server in the foreground.
# Adapted from Lightdash's docker/init-minio.sh.
set -e
minio server /data --address :9100 &
until mc alias set local http://localhost:9100 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1; do
  sleep 1
done
mc mb --ignore-existing local/lightdash
wait
