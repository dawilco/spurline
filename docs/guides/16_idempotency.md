# Idempotency

Idempotency prevents duplicate side effects when the same tool call is retried.

If an idempotent tool is called again with the same idempotency key inside its TTL window, Spurline returns the cached result instead of executing the tool again.

---

## What Idempotency Is

For side-effecting tools, retries can be dangerous:

- Sending the same email twice
- Charging a card twice
- Creating duplicate pull requests
- Posting duplicate messages
- Triggering duplicate deployments

Idempotency makes repeat calls safe by turning "same intent" into "same result".

---

## Which Tools Need It

Use idempotency for irreversible or externally visible side effects:

- Payments and billing operations
- Email or SMS sending
- PR/issue creation and message posting
- Deployment or release triggers

Tools that only read data generally should not be idempotent.

---

## Which Tools Do Not Need It

Avoid idempotency for read-only or time-varying operations:

- Searches and lookups
- File reads or API fetches
- Time-based/status queries
- Data discovery tools where freshness matters

---

## Declaring a Tool as Idempotent

```ruby
class ChargePayment < Spurline::Tools::Base
  tool_name :charge_payment
  idempotent true
  idempotency_key :transaction_id
  idempotency_ttl 3600 # 1 hour

  def call(transaction_id:, amount:, currency:)
    # Charged only once per transaction_id
  end
end
```

---

## Key Computation

`Spurline::Tools::Idempotency::KeyComputer` supports three modes:

1. Default (all arguments)

```ruby
# SHA256 of canonical JSON with recursively sorted keys
idempotency_key = KeyComputer.compute(tool_name: :charge_payment, args: args)
```

2. Named params

```ruby
idempotency_key :transaction_id
idempotency_key :order_id, :line_item_id
```

Only those params are included in key hashing.

3. Custom lambda

```ruby
idempotency_key_fn ->(args) { "#{args[:order_id]}-#{args[:action]}" }
```

The final key format is always `"tool_name:computed_value"`.

---

## TTL Configuration

Per-tool TTL:

```ruby
idempotency_ttl 3600
```

Global default (after integration wiring):

```ruby
Spurline.configure do |c|
  c.idempotency_default_ttl = 86_400
end
```

Expired entries are cleaned lazily when checked or during explicit cleanup.

---

## Conflict Detection

If the same idempotency key appears with a different argument hash, Spurline raises `IdempotencyKeyConflictError`.

That is a caller bug: key derivation must uniquely represent the intended operation.

---

## Audit Trail (After Integration)

Tool call entries include idempotency metadata:

- `idempotency_key`
- `was_cached`
- `cache_age_ms`

This keeps duplicate-suppression behavior explicit in diagnostics and incident review.
