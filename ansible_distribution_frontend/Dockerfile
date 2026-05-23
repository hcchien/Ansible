FROM node:22-alpine

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=8080

WORKDIR /app

COPY package.json ./
COPY index.html server.mjs ./
COPY src ./src

USER node

EXPOSE 8080

CMD ["node", "server.mjs"]
