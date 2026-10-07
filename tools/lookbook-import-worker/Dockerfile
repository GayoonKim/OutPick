FROM node:24-slim AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM deps AS build
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM build AS local-performance
COPY scripts ./scripts
COPY .eslintrc.cjs ./
CMD ["npm", "test"]

FROM node:24-slim AS runtime
ENV NODE_ENV=production
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npx playwright install --with-deps chromium
COPY --from=build /app/lib ./lib
COPY fixtures/performance-remote-input-amd64.json ./fixtures/performance-remote-input-amd64.json
COPY scripts/queue-linux-smoke.mjs scripts/queue-linux-sigterm-child.mjs ./scripts/
EXPOSE 8080
CMD ["node", "lib/index.js"]
