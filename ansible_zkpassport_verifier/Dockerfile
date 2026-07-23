FROM node:22-bookworm-slim
WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile
COPY src ./src
COPY circuits ./circuits
RUN pnpm build && pnpm prune --prod
USER node
ENV PORT=8080
CMD ["npm", "start"]
