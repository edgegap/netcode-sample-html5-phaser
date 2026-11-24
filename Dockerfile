# Game server image (linux/amd64):
#   docker build --platform linux/amd64 -t registry.edgegap.com/<project>/splat-arena:<tag> .
#   docker run --rm -p 7777:7777 registry.edgegap.com/<project>/splat-arena:<tag>
# Only the Node.js server goes in the image. The HTML5 client (client/) is a static page you host
# anywhere: GitHub Pages, itch.io, your own site.
FROM node:22-slim
WORKDIR /app
ENV NODE_ENV=production PORT=7777
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY server ./server
# Internal port. The Edgegap app version maps it as "gameport", protocol WS, TLS Upgrade on.
EXPOSE 7777/tcp
USER node
# Node is PID 1, so it receives Edgegap's SIGTERM directly (no shell wrapper).
CMD ["node", "server/main.js"]
