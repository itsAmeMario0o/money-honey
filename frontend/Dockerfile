# Multi-stage build for the React SPA.
# Stage 1 builds the static bundle with Node.
# Stage 2 serves the bundle with nginx.

FROM node:20-alpine AS builder

WORKDIR /build

COPY package.json package-lock.json* ./

RUN npm install

COPY . .

RUN npm run build


FROM nginx:1.29.6-alpine3.23 AS runtime

# Pick up any Alpine package fixes released since the image tag was
# cut. Belt-and-suspenders against base-image CVE drift between tag
# refreshes. Clears the apk cache to keep the image small.
RUN apk upgrade --no-cache

# Non-root user per CLAUDE.md Dockerfile rules
RUN adduser -D -u 10001 honey

COPY --from=builder /build/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Nginx needs writable cache dirs for the non-root user
RUN chown -R honey:honey /var/cache/nginx /var/run /usr/share/nginx/html \
    && touch /var/run/nginx.pid \
    && chown honey:honey /var/run/nginx.pid

USER honey

EXPOSE 3000

CMD ["nginx", "-g", "daemon off;"]
