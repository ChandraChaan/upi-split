# Security notes

## What the rules enforce

Without Cloud Functions, `firestore.rules` is the only server-side check.

- Businesses are isolated, and staff reach only their assigned stores.
- Deactivating a member cuts access, including writes queued on their phone.
- Khata entries, stock moves and supplier transactions cannot be edited or deleted.
- Bills must add up: total equals subtotal less discount, and payments equal total.
- Cashiers cannot change prices, credit limits or staff, or void anything.
- Invites are single use, expire after 7 days, and cannot be upgraded by the joiner.

## Known limits of a client-only design

- **Daily totals and stored balances are written by the app.** A signed-in staff
  member with a modified app could write wrong numbers to their own store. Ledger
  entries stay immutable, and a balance can be rebuilt from its ledger with
  `recalculateCustomerBalance`. Closing this fully needs Cloud Functions, and so
  the paid Blaze plan.
- **Cashiers can technically read cost prices.** The app hides them, but they are
  stored on the same product and bill documents that a cashier needs for billing.
- **Device clocks set business dates.** Offline sales need a time without a
  server, so a phone with a wrong date records under the wrong day.
- **Offline data sits unencrypted in the app's private storage** on the phone.

## Before going live

- Create an upload keystore and `android/key.properties`. Never commit either.
- Turn on Firebase App Check.
- Add a Firebase budget alert.
- Publish a privacy policy: the app stores customers' names, phone numbers and
  dues. Check your obligations under India's DPDP Act.
