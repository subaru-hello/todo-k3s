# ビルドステージ（共通）
FROM node:24-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src ./src

RUN npm run build

# 開発環境用（デバッグ可能）
FROM node:24-alpine AS development

WORKDIR /app

ENV NODE_ENV=development

COPY package*.json ./
RUN npm ci --only=production

COPY --from=builder /app/dist ./dist

EXPOSE 3000

CMD ["node", "dist/index.js"]

# 本番環境用（distroless、セキュアだがシェルなし）
FROM gcr.io/distroless/nodejs20-debian12 AS production

WORKDIR /app

ENV NODE_ENV=production

COPY package*.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist

EXPOSE 3000

CMD ["dist/index.js"]