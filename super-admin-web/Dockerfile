# ─── Stage 1: Build Angular ───────────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
ENV NODE_OPTIONS="--max-old-space-size=512"
RUN npm ci

COPY . .
RUN npx ng build --configuration production

# ─── Stage 2: Serve with Nginx ────────────────────────────────────────────────
FROM nginx:alpine AS runner

# Remove default nginx page
RUN rm -rf /usr/share/nginx/html/*

# Copy built Angular app
COPY --from=builder /app/dist/super-admin-web/browser /usr/share/nginx/html

# Copy custom nginx config and basic auth file
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY infra.htpasswd /etc/nginx/infra.htpasswd

EXPOSE 80 8091

CMD ["nginx", "-g", "daemon off;"]
