# The consumer uses only Bun built-ins (WebSocket, fetch, node:fs), so there are
# no dependencies to install and nothing to build.
FROM oven/bun:1-slim
WORKDIR /app
COPY consumer.ts .
CMD ["bun", "run", "consumer.ts"]
