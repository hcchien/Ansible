# Pin the base image to an immutable multi-arch index digest instead of the
# floating `node:22-alpine` tag, so rebuilds are reproducible and a
# compromised/retagged upstream cannot silently change what ships.
# Digest resolved from node:22-alpine (Node 22.x on Alpine 3.22).
# To update: `docker buildx imagetools inspect node:22-alpine` and replace the
# digest below, bumping the human-readable comment.
FROM node:22-alpine@sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2

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
