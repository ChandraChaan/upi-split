# Account deletion

Google Play requires apps that create accounts to let people delete them, both
in the app and from the web. The public promise is in the privacy policy and on
https://chandrachaan.github.io/app-policies/upi-split/delete-account.html:
a shop is erased within **30 days** of the request.

## In the app (Shop → More → Settings → Delete account)

`SessionController.deleteAccount` asks for the password again, then:

1. **Owner:** sets `deletionRequestedAt` and `deletionRequestedBy` on
   `businesses/{bid}`. The rules already allow an owner to update their
   business, so no rules change was needed.
2. Deletes `users/{uid}`.
3. Deletes the Firebase Auth user.

The app cannot erase the shop's records itself, because the rules keep ledgers
append-only and forbid deletes. Erasing is a developer step.

A staff member's entries stay in the owner's books, because they are the shop's
records. Their member record stays too, so the owner still sees who wrote what.

## Requests from the web

People email chandrachaan.apps@gmail.com from their account's address. Find the
user under Authentication, delete them, and if they own a business, erase it as
below.

## Erasing a flagged business (do this at least every 30 days)

1. In the Firebase console, open Firestore for `kirana-mitra-chandra`. Filter
   `businesses` on `deletionRequestedAt` (it exists only on flagged ones).
2. For each flagged business `{bid}`:
   - Under Authentication, delete the remaining staff accounts that belong only
     to this shop (emails are in `businesses/{bid}/members`). Skip anyone who
     asked to keep their login.
   - Filter `users` on `businessId == {bid}` and delete those documents, so
     staff who sign in again get the "start or join a shop" screen.
   - Delete open invites: filter `invites` on `businessId == {bid}`.
   - Erase the business and everything under it:

     ```bash
     firebase firestore:delete "businesses/{bid}" --recursive --project kirana-mitra-chandra
     ```
3. Note the date in your own records in case anyone asks later.
