# Authorize.Net Webhook Registration

**Date:** 2026-03-24
**Recipient:** Josh (human, operational)

## What

The server now has a webhook endpoint at:

```
POST https://<your-domain>/v1/webhooks/authorizenet
```

This endpoint receives notifications from Authorize.Net when payments are captured, voided, refunded, or flagged for fraud. It must be registered in the Authorize.Net merchant dashboard before it will receive any events.

## Steps

1. Log into the **Authorize.Net merchant dashboard** (sandbox for testing first, production when ready)
2. Navigate to **Account → Webhooks**
3. Click **Add Endpoint**
4. Enter the URL: `https://<production-domain>/v1/webhooks/authorizenet`
5. Subscribe to these event types:
   - `net.authorize.payment.authcapture.created`
   - `net.authorize.payment.void.created`
   - `net.authorize.payment.refund.created`
   - `net.authorize.payment.fraud.declined`
6. Set status to **Active**
7. Save

## Signature Key

The webhook uses HMAC-SHA512 signature verification. The **Signature Key** is configured via the `AUTHORIZENET_SIGNATURE_KEY` env var on the server. This key is generated in the Authorize.Net dashboard under **Account → API Credentials & Keys → Signature Key**. The server and dashboard must use the same key.

## Testing

After registration, create a test booking in sandbox mode. The `authcapture.created` webhook should fire. Check server logs for:

```
webhook received event_type=net.authorize.payment.authcapture.created
```

If you see `webhook signature verification failed`, the signature key doesn't match between the server env var and the dashboard.

## When

This can be done at any time. The endpoint is deployed and will accept webhooks as soon as they're registered. Until registration, no webhooks are delivered — existing payment flows (charge, void, refund) work fine without webhooks. The webhook adds reconciliation and held-transaction support.
