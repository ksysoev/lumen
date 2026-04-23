# ADR 0001: V1 agent discovery and topic messaging architecture

- Status: Proposed
- Date: 2026-04-23
- Owners: Lumen maintainers

## Context

Lumen currently provides a service scaffold with:

- HTTP server and routing in `pkg/api`
- business orchestration in `pkg/core`
- Redis connectivity available in `pkg/cmd` and repository packages

The next milestone introduces core product behavior: agent registration, topic subscription, message publish, and message consume/ack flows.

The architecture must keep implementation simple for v1, align with existing Go package boundaries, and provide reliable delivery guarantees suitable for service-to-service messaging.

## Decision

Use HTTP JSON APIs for control and data plane operations, backed by Redis for both discovery state and topic messaging.

### Layering

- `pkg/api`: HTTP handlers, request validation, status mapping, response envelope
- `pkg/core`: use-case orchestration and domain validation
- `pkg/repo`: Redis-backed persistence and stream operations

### API contract (v1)

#### 1) Register agent

`POST /v1/agents`

Request:

```json
{
  "agent_id": "agent-123",
  "display_name": "payments-worker",
  "endpoint": "http://payments-worker:8080",
  "capabilities": ["payments", "refunds"],
  "metadata": {
    "zone": "us-east-1a"
  },
  "lease_ttl_sec": 30
}
```

Response (`201 Created` on first registration, `200 OK` on idempotent re-registration):

```json
{
  "agent_id": "agent-123",
  "lease_ttl_sec": 30,
  "lease_expires_at": "2026-04-23T18:40:00Z"
}
```

Required fields: `agent_id`.

#### 2) Heartbeat

`PUT /v1/agents/{agent_id}/heartbeat`

Request body: empty.

Response (`200 OK`):

```json
{
  "agent_id": "agent-123",
  "lease_expires_at": "2026-04-23T18:40:30Z"
}
```

#### 3) Unregister agent

`DELETE /v1/agents/{agent_id}`

Request body: empty.

Response: `204 No Content`.

#### 4) Subscribe to topic

`PUT /v1/agents/{agent_id}/subscriptions/{topic}`

Request body: empty.

Response: `204 No Content`.

#### 5) Unsubscribe from topic

`DELETE /v1/agents/{agent_id}/subscriptions/{topic}`

Request body: empty.

Response: `204 No Content`.

#### 6) Publish message

`POST /v1/topics/{topic}/messages`

Request:

```json
{
  "publisher_agent_id": "agent-123",
  "payload": {
    "event": "payment.completed",
    "payment_id": "p-001"
  },
  "attributes": {
    "schema": "payment.v1"
  }
}
```

Response (`202 Accepted`):

```json
{
  "message_id": "1745452861000-0",
  "topic": "payments",
  "published_at": "2026-04-23T18:41:01Z"
}
```

Required fields: `payload`.

#### 7) Consume messages

`GET /v1/agents/{agent_id}/subscriptions/{topic}/messages?count=10&block_ms=30000`

Query defaults and limits:

- `count`: default `1`, max `100`
- `block_ms`: default `30000`, max `60000`

Response (`200 OK`):

```json
{
  "messages": [
    {
      "message_id": "1745452861000-0",
      "topic": "payments",
      "publisher_agent_id": "agent-123",
      "payload": {
        "event": "payment.completed",
        "payment_id": "p-001"
      },
      "attributes": {
        "schema": "payment.v1"
      },
      "published_at": "2026-04-23T18:41:01Z"
    }
  ]
}
```

#### 8) Ack consumed messages

`POST /v1/agents/{agent_id}/subscriptions/{topic}/acks`

Request:

```json
{
  "message_ids": [
    "1745452861000-0",
    "1745452862000-0"
  ]
}
```

Response (`200 OK`):

```json
{
  "acked": 2
}
```

Required fields: `message_ids` (non-empty).

### Redis data model

#### Agent registry and leases

- Key: `agent:{agent_id}` (hash)
  - fields: `agent_id`, `display_name`, `endpoint`, `capabilities_json`, `metadata_json`, `registered_at`, `last_seen_at`, `lease_ttl_sec`
  - TTL: lease expiration (default `30s`)

#### Subscription index

- Key: `agent:{agent_id}:topics` (set of topics)
- Key: `topic:{topic}:agents` (set of agent IDs)

Both sets are updated together for consistency on subscribe/unsubscribe.

#### Topic message storage

- Key: `stream:topic:{topic}` (Redis stream)
- Stream entry fields: `publisher_agent_id`, `payload_json`, `attributes_json`, `published_at`

#### Consumer groups

- Group name: `group:agent:{agent_id}:topic:{topic}`
- Group creation: lazy and idempotent during first consume

#### Retention

- Apply approximate trim per topic stream: `MAXLEN ~ <topic_max_len>`
- v1 default: `10000` entries per topic, configurable later

#### Cleanup on unregister

- Delete `agent:{agent_id}`
- Read and remove topic memberships from both index sets
- Delete `agent:{agent_id}:topics`
- Leave stream data untouched (topic data is shared)

### Delivery guarantees and idempotency

#### Delivery semantics

- Delivery is `at-least-once`
- Consumers must ack processed messages
- Unacked messages remain pending and can be re-delivered
- Ordering is guaranteed by Redis stream entry ID within a topic stream

#### Idempotency rules

- Register: idempotent by `agent_id` (first call creates, repeated call renews metadata/lease)
- Heartbeat: idempotent lease renewal
- Unregister: idempotent (`204` even if already absent)
- Subscribe: idempotent (`204` if already subscribed)
- Unsubscribe: idempotent (`204` if already unsubscribed)
- Ack: idempotent (already acked IDs are ignored)
- Publish: non-idempotent in v1 (retries can produce duplicates)

### Error model and HTTP mapping

All error responses use JSON envelope:

```json
{
  "error": {
    "code": "invalid_argument",
    "message": "topic is invalid",
    "request_id": "9f2e33af-7fd6-4b9d-bf7e-0f0b9e6d286d"
  }
}
```

Error code mapping:

- `invalid_argument` -> `400 Bad Request`
- `not_found` -> `404 Not Found`
- `conflict` -> `409 Conflict`
- `unprocessable_entity` -> `422 Unprocessable Entity`
- `unavailable` -> `503 Service Unavailable`
- `internal` -> `500 Internal Server Error`

### Validation constraints (v1)

- `agent_id`: non-empty string, max 128 chars
- `topic`: `[a-z0-9._-]{1,128}`
- `message_ids`: 1..100 per ack request
- `payload`: required JSON object, max 256 KB per message

## Alternatives considered

### Push delivery via webhooks

Rejected for v1 due to significantly higher operational complexity (delivery retries, backoff, authentication, endpoint health tracking).

### Exactly-once delivery

Rejected for v1 due to complexity and high implementation cost in Redis-backed architecture.

### Kafka/NATS as backend in v1

Rejected for v1 to keep deployment and maintenance simple and align with existing Redis usage.

## Consequences

Positive:

- Fast delivery of a functional v1 with clear contracts
- Simple operational footprint (HTTP + Redis)
- Clear path to incremental hardening (auth, dead-letter queues, producer idempotency)

Trade-offs:

- Duplicate handling required by consumers
- No push-delivery primitives in v1
- Retention and payload limits are conservative defaults

## Non-goals (v1)

- Authentication and authorization model
- Websocket/SSE/webhook push delivery
- Exactly-once semantics
- Cross-topic transactions
- Dead-letter queue and replay admin API

## Open questions

1. Should `agent_id` be strictly UUID format or keep generic string?
2. Should topic retention be global default only, or configurable per topic in v1?
3. Should `publisher_agent_id` be required for all publishes?
4. Do we need a dedicated `GET /v1/agents/{agent_id}` endpoint in v1?
