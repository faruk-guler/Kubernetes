# 🔥 Node.js Multi-stage Dockerfile (Modern)

# --- Stage 1: Builder ---
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# --- Stage 2: Production ---
FROM node:18-alpine
ENV NODE_ENV=production
WORKDIR /app

# GÜVENLİK: Root olmayan kullanıcı
USER node

COPY --from=builder /app/package*.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist

EXPOSE 3000
CMD ["node", "dist/main.js"]
