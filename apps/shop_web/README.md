# Kirana Mitra Shop for the web

The Shop from the UPI Split Android app, as a web app for iPhones and any
phone without the Android app. It is served at
<https://kirana-mitra-chandra.web.app/shop/>.

On an iPhone, open that link in Safari, tap Share, then **Add to Home Screen**.
It then opens full screen with its own icon, signs in with the same account,
and shows the same shop data as the Android app.

This project has no screens of its own. It depends on the app at the repo root
and only adds the web entry point (`lib/main.dart`), the web Firebase settings,
and the page, manifest and icons in `web/`. The icon's source is
`design/icon.svg`.

```bash
flutter run -d chrome --dart-define=USE_EMULATOR=true   # against local emulators
flutter test
```

Build and deploy together with the web admin from the repo root:

```bash
./scripts/build_hosting.sh && firebase deploy --only hosting
```

Limits compared with the Android app: it needs the internet the first time it
opens; Telugu text appears once its font has downloaded; and receipt images
share through the browser's share sheet.
