FROM node:20-bookworm-slim AS build
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ \
  && rm -rf /var/lib/apt/lists/*
COPY package.json ./
RUN npm install --omit=dev
COPY server.js ./
COPY public ./public

FROM node:20-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production \
    PORT=3000 \
    DB_PATH=/data/todo.db \
    APP_ENV=local \
    APP_VERSION=0.1.0
RUN mkdir -p /data && chown -R node:node /data /app
COPY --from=build --chown=node:node /app /app
USER node
EXPOSE 3000
VOLUME ["/data"]
CMD ["node", "server.js"]
