# syntax=docker/dockerfile:1
#
# CloudScale Lab: multi-stage build producing a small, non-root Node.js image.
# Build context is the repository root; only ./app is copied (see .dockerignore).
#
#   docker build --platform linux/amd64 -t cloudscale-lab:local .
#
# t3.micro instances are x86_64, so images that run on EC2 must be linux/amd64.

ARG NODE_VERSION=24

# ---- Stage 1: install dependencies exactly as pinned in package-lock.json ----
FROM node:${NODE_VERSION}-alpine AS deps
WORKDIR /app
COPY app/package.json app/package-lock.json ./
RUN npm ci --no-audit --no-fund

# ---- Stage 2: build the Next.js standalone output ----
FROM node:${NODE_VERSION}-alpine AS builder
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1
COPY --from=deps /app/node_modules ./node_modules
COPY app/ ./
RUN npm run build

# ---- Stage 3: minimal runtime image ----
FROM node:${NODE_VERSION}-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0

# Standalone output = server.js + only the node_modules it actually needs.
COPY --from=builder --chown=node:node /app/.next/standalone ./
COPY --from=builder --chown=node:node /app/.next/static ./.next/static

# Version label shown in the UI and /api/instance (CI passes the git SHA).
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

# The official Node image ships an unprivileged "node" user.
USER node

EXPOSE 3000

# Docker-level health check (the ALB performs its own check on /api/health).
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server.js"]
