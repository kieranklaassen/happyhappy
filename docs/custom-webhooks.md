# Custom inbound webhooks

A custom webhook source lets any product send customer messages to happyhappy over HTTPS. Each message becomes part of an item in the feed, exactly like a Slack or Intercom message. In sync mode the same request also classifies the message and returns the labels, so a product can use happyhappy as its classifier.

## Set up a source

1. Open **Sources**, choose **Add source**, and pick the kind **Custom webhook**.
2. Name it and choose its product. The product is required: messages land on it unless classification names another product.
3. After you create it, the edit page shows the **Webhook URL** and the **Signing secret**. The URL looks like `https://<happyhappy host>/webhooks/custom/<token>`.

Keep the secret on your server. **Rotate secret** on the same page issues a new one, and requests signed with the old secret fail from that moment.

The server needs Active Record encryption keys to store secrets: set `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`, and `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` (generate them with `bin/rails db:encryption:init`). Changing them later makes stored secrets unreadable, so every custom source would need a new secret.

## Request

`POST <webhook URL>` with `Content-Type: application/json`, the JSON body below, and an `X-Happyhappy-Signature` header.

```json
{
  "id": "fb-123",
  "text": "Cora archived my invoice email and now I cannot find it anywhere.",
  "author": { "name": "Dana", "handle": "@dana", "email": "dana@example.com" },
  "thread_key": "ticket-42",
  "permalink": "https://cora.computer/feedback/123",
  "occurred_at": "2026-09-24T18:30:00Z",
  "metadata": { "plan": "pro" }
}
```

| Field | Required | Meaning |
|---|---|---|
| `text` | yes | The customer's message, a non-empty string. |
| `id` | no | Your id for this message, a string or integer. The same `id` twice stores one message. Without it, happyhappy uses a SHA-256 hash of the raw body, so an identical resend is still a duplicate. |
| `thread_key` | no | Groups messages into one item, such as a ticket or conversation id. Defaults to the message id, so each message is its own item. |
| `author` | no | A string (taken as the name) or an object with any of `name`, `handle`, `email`. |
| `permalink` | no | A link back to the message in your product. |
| `occurred_at` | no | ISO 8601 time the customer wrote it. Defaults to the time of the request. |
| `metadata` | no | Any JSON object. It is stored with the message but not classified. |

The whole body is kept as the message's raw payload.

## Signature

Every request carries:

```
X-Happyhappy-Signature: t=<unix time>,v1=<signature>
```

where `<signature>` is the lowercase hex HMAC-SHA256 of the string `<unix time>.<raw body>`, keyed with the source's signing secret. Sign the exact bytes you send; reformatting the JSON after signing breaks the signature.

happyhappy rejects a request when the signature does not match or when `t` is more than 5 minutes away from its clock. While you move to a new secret you may send several `v1` values, as in `t=1790000000,v1=<new>,v1=<old>`; any match is accepted. Outbound webhooks from happyhappy use the same scheme.

## Sync mode

Add `?sync=true` to the URL to classify inline. happyhappy stores the message, asks Jev for labels, and answers `200` with them. If Jev does not answer within 10 seconds, or fails, the response is still `200` with `"classification": "pending"` and `"labels": null`; the message stays queued and is classified in the background. A resent duplicate is not classified again: the response carries whatever labels the stored message already has.

Without `sync`, the endpoint answers `202` as soon as the message is stored, with `"classification": "pending"`.

## Responses

Stored message (`202`, or `200` in sync mode):

```json
{
  "item_id": 2,
  "message_id": 2,
  "duplicate": false,
  "classification": "classified",
  "item_status": "new",
  "labels": {
    "relevant": { "probability": 0.97 },
    "product": { "value": "cora", "probability": 1.0, "probabilities": { "cora": 1.0, "none": 0.0 } },
    "category": { "value": "other", "probability": 1.0, "probabilities": { "other": 1.0, "bug": 0.0 } },
    "sentiment": {
      "value": "praise",
      "probability": 1.0,
      "probabilities": { "praise": 1.0, "complaint": 0.0, "question": 0.0, "neutral": 0.0 }
    },
    "anger": { "probability": 0.01 }
  }
}
```

`labels` describe this message as Jev read it: `product.value` is a product slug or `none`, `category.value` is a category name or `other`, and `sentiment.value` is one of `complaint`, `praise`, `question`, `neutral`. The item in the feed rolls these up with the rest of its thread and may differ. `item_status` is the item's workflow status (`new`, `claimed`, `in_progress`, `handled`, `dismissed`).

Errors answer with `{ "error": "<reason>" }`:

| Status | When |
|---|---|
| `401` | Missing, wrong, or expired signature. Nothing is stored. |
| `404` | Unknown token, or the source is paused. |
| `413` | Body over 16 KB. Nothing is stored. |
| `422` | Body is not a JSON object, `text` is missing, or a field has the wrong type. The reason names the field. |
| `429` | More than 60 sync requests in one minute for this source. Requests without `sync` are not limited. |

## Limits

- Body size: 16 KB (16,384 bytes), for every request.
- Signature window: 5 minutes either side of happyhappy's clock.
- Sync mode: 60 requests per minute per source, and at most 10 seconds waiting for Jev.

## Example

This signs with `openssl` and sends one message in sync mode. Replace the URL and secret with the values from the source's edit page.

```bash
URL="https://happyhappy.example.com/webhooks/custom/<token>"
SECRET="hhsec_<your signing secret>"
BODY='{"id":"fb-123","text":"Cora archived my invoice email and now I cannot find it anywhere.","author":{"name":"Dana","email":"dana@example.com"},"thread_key":"ticket-42","permalink":"https://cora.computer/feedback/123","metadata":{"plan":"pro"}}'

TIMESTAMP=$(date +%s)
SIGNATURE=$(printf '%s.%s' "$TIMESTAMP" "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $NF}')

curl -sS -X POST "$URL?sync=true" \
  -H "Content-Type: application/json" \
  -H "X-Happyhappy-Signature: t=$TIMESTAMP,v1=$SIGNATURE" \
  --data-binary "$BODY"
```

Drop `?sync=true` to get a `202` without labels. Use `--data-binary`, not `-d`, so curl sends the body byte for byte.

The same signature in Ruby:

```ruby
timestamp = Time.now.to_i
signature = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
headers = { "X-Happyhappy-Signature" => "t=#{timestamp},v1=#{signature}" }
```
