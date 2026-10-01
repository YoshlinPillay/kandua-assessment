# Altimate Code (MIT), pinned, for the evaluation in docs/altimate-evaluation.md. Not part of the runtime stack.
FROM node:24-bookworm-slim
RUN npm install -g altimate-code@0.12.4 && npm cache clean --force
ENV HOME=/tmp/home
RUN mkdir -p /tmp/home && chmod 777 /tmp/home
ENTRYPOINT ["altimate-code"]
