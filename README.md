# Lumen

[![Tests](https://github.com/ksysoev/lumen/actions/workflows/tests.yml/badge.svg)](https://github.com/ksysoev/lumen/actions/workflows/tests.yml)
[![Go Report Card](https://goreportcard.com/badge/github.com/ksysoev/lumen)](https://goreportcard.com/report/github.com/ksysoev/lumen)
[![Go Reference](https://pkg.go.dev/badge/github.com/ksysoev/lumen.svg)](https://pkg.go.dev/github.com/ksysoev/lumen)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Lumen is an agent discovery and messaging platform

## Architecture Decisions

- `docs/adr/0001-v1-agent-discovery-messaging.md`: v1 API contract, Redis data model, and delivery guarantees

## Installation

## Building from Source

```sh
CGO_ENABLED=0 go build -o lumen -ldflags "-X main.version=dev -X main.name=lumen" ./cmd/lumen/main.go
```

### Using Go

If you have Go installed, you can install Lumen directly:

```sh
go install github.com/ksysoev/lumen/cmd/lumen@latest
```


## Using

```sh
lumen --log-level=debug --log-text=true --config=runtime/config.yml
```

## License

Lumen is licensed under the MIT License. See the LICENSE file for more details.
