FROM golang:1.26.1-alpine AS builder

ARG VERSION=${VERSION}

WORKDIR /app

COPY . .
RUN go mod download

RUN CGO_ENABLED=0 go build -o lumen -ldflags "-X main.version=$VERSION -X main.name=lumen" ./cmd/lumen/main.go

FROM scratch

COPY --from=builder /app/lumen .
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

ENTRYPOINT ["/lumen"]
