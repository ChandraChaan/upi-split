# Kirana Mitra (కిరాణా మిత్ర)

Store management for Indian kirana shops: customer khata, billing, inventory,
suppliers, expenses and profit, in Telugu and English. It keeps working with no
internet and syncs by itself when the connection returns.

| Part | Path | Used by |
|---|---|---|
| Android app | `lib/kirana`, opened from the Shop button in UPI Split | Owners, managers, cashiers |
| Web admin | `apps/admin` | Owners and managers, across all stores |
| Shared logic | `packages/kirana_core` | Both apps |
| Security rules | `firestore.rules` | The only server-side protection |
| Rule tests and demo data | `firebase_tests` | Development |

It needs Firebase Auth, Firestore and Hosting only. There are no Cloud Functions,
so it runs on the free Spark plan.

## How offline works

- Every sale, payment and stock change is a Firestore write batch, applied on the
  phone at once and uploaded when there is a connection.
- Balances, stock and daily totals change only through atomic increments, so two
  phones working offline add up instead of overwriting each other.
- Ledgers are append-only. A mistake is fixed by a reversing entry or by voiding
  the bill, which also corrects stock and the original day's totals.
- Stock can go negative if two offline phones sell the last item. It is shown
  rather than blocked, because the sale really happened.
- Money is whole paise and quantity is thousandths of a unit. No doubles.
- Reports read one small rollup document per store per day.

## Roles

| | Owner | Manager | Cashier |
|---|---|---|---|
| Sell, record payments, add expenses | Yes | Yes | Yes |
| Products, stock, suppliers, void bills, reports | Yes | Assigned stores | No |
| Web admin | Yes | Assigned stores | No |
| Staff and stores | Yes | No | No |

Staff join with an 8-character invite code from the web admin's Staff page.

## Running locally

Needs Flutter, the Firebase CLI, and Java 21 or newer for the emulators.

```bash
firebase emulators:start --only auth,firestore --project demo-kirana
```

```bash
cd firebase_tests && npm ci && npm run seed
```

```bash
flutter run --dart-define=USE_EMULATOR=true
```

```bash
cd apps/admin && flutter run -d chrome --dart-define=USE_EMULATOR=true
```

Emulator builds use a demo project and a fake key, so they cannot reach
production. Demo sign-ins are in `firebase_tests/seed.mjs`.

## Checks

```bash
./scripts/test_all.sh
```

## Release

```bash
firebase deploy --only firestore,auth
```

```bash
cd apps/admin && flutter build web --release && cd ../.. && firebase deploy --only hosting
```

For Play Store builds, run `flutter build appbundle --release` at the repo root.
`android/key.properties` must point at the UPI Split upload keystore. See
[KIRANA_SECURITY.md](KIRANA_SECURITY.md).
