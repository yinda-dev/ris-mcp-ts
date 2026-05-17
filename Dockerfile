FROM node:24-alpine AS builder

RUN apk upgrade --no-cache zlib
RUN corepack enable pnpm
WORKDIR /app
ENV HUSKY=0
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY tsconfig.json ./
COPY src/ ./src/
RUN pnpm run build
RUN pnpm install --frozen-lockfile --prod --ignore-scripts

FROM node:24-alpine

RUN apk upgrade --no-cache zlib \
    # ca-certificates provides update-ca-certificates and the system CA bundle
 && apk add --no-cache ca-certificates \
 && rm -rf /usr/local/lib/node_modules/npm \
    /usr/local/bin/npm /usr/local/bin/npx

WORKDIR /app
ENV HUSKY=0
COPY --from=builder /app/node_modules/ ./node_modules/
COPY --from=builder /app/dist/ ./dist/

# Copy and prepare the entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    # Create the mount-point so the directory always exists even without a bind-mount
 && mkdir -p /opt/custom-certificates \
    # Ensure the entrypoint can write to the system CA directory (runs as root before dropping to node)
 && chmod 755 /usr/local/share/ca-certificates

EXPOSE 3000

# The entrypoint runs as root so it can install certificates, then execs the CMD as the node user.
# Note: USER node is intentionally placed after the entrypoint copies so the script can
# call update-ca-certificates (requires root). The script itself drops privileges via exec "$@".
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "dist/http.js"]
