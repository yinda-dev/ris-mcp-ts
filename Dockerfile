FROM node:24-alpine AS builder

RUN corepack enable pnpm
WORKDIR /app
ENV HUSKY=0
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY tsconfig.json vite.ui.config.ts ./
COPY src/ ./src/
# Widget sources: `pnpm run build` bundles them into src/generated/ first, so
# the compiled server carries the HTML in dist/generated/ — no runtime file
# lookup, nothing extra to copy into the runtime stage.
COPY ui/ ./ui/
COPY scripts/ ./scripts/
# The build runs the three-project typecheck (root, ui, tests) — the host-sim
# suite itself never runs here, but its tsconfig and the files it includes must
# exist or `tsc -p tests/tsconfig.json` fails the image build (v1.6.0 lesson:
# the image build only runs on tag pushes, so a PR never catches this).
COPY tests/ ./tests/
COPY playwright.host.config.ts ./
RUN pnpm run build

FROM node:24-alpine

# ca-certificates: system CA bundle + update-ca-certificates.
# su-exec: lets the entrypoint drop from root to the node user.
RUN corepack enable pnpm \
 && apk add --no-cache ca-certificates su-exec
WORKDIR /app
ENV HUSKY=0
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod --ignore-scripts
COPY --from=builder /app/dist/ ./dist/

# Runtime environment. Set AFTER the --prod install so it does not interfere
# with dependency resolution. Enables production behaviour in http.ts (the
# NODE_ENV !== 'test' gate still passes, so app.listen/sweep/shutdown run).
ENV NODE_ENV=production

# The entrypoint installs custom CA certificates (mounted at
# /opt/custom-certificates) as root and then drops to the node user.
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
 && mkdir -p /opt/custom-certificates /usr/local/share/ca-certificates

EXPOSE 3000
# No `USER node` here on purpose: the entrypoint needs root for
# update-ca-certificates and then runs the CMD as node via su-exec.

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "dist/http.js"]
