# Multi-stage: build with the full toolchain, run with only what adapter-node
# actually needs at runtime (its own package.json lists just the production
# dependencies content.ts uses — gray-matter, marked, shiki — so `npm ci
# --omit=dev` in the runtime stage is genuinely smaller than copying the
# build stage's node_modules wholesale).
FROM node:22-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:22-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY --from=build /app/build ./build

# content/ is deliberately NOT baked into this image — it's bind-mounted at
# /content by docker-compose.yml instead. loadDoc()/docExists() read files
# from disk per request, not at startup, so a content-only change (a new
# exercise, a guide fix) takes effect on the *next request*, with no image
# rebuild and no container restart. CONTENT_ROOT here is the default for
# running this image standalone (e.g. `docker run -v ./content:/content`);
# compose sets the same value explicitly alongside its own mount.
ENV CONTENT_ROOT=/content

EXPOSE 3000
ENV PORT=3000
ENV BODY_SIZE_LIMIT=Infinity
CMD ["node", "build/index.js"]
