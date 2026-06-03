ARG GO_IMAGE=golang:1.22-bookworm
ARG RUNNER_IMAGE=gcr.io/distroless/static-debian12:nonroot

FROM ${GO_IMAGE} AS build

ENV CGO_ENABLED=0 \
    GOOS=linux

WORKDIR /app

# go.sum is optional today (issuer uses only the standard library) but is copied
# when present so future module dependencies build reproducibly.
COPY go.mod ./
COPY go.su[m] ./
RUN go mod download

COPY cmd ./cmd
COPY internal ./internal

RUN go build -trimpath -ldflags="-s -w" -o /out/ansible_issuer ./cmd/server

FROM ${RUNNER_IMAGE}

ENV PORT=8080

WORKDIR /app

COPY --from=build /out/ansible_issuer /app/ansible_issuer

EXPOSE 8080

USER nonroot:nonroot

ENTRYPOINT ["/app/ansible_issuer"]
