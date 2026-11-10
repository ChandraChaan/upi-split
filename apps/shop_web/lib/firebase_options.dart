import 'package:firebase_core/firebase_core.dart';

/// The project's web app, shared with the web admin. Both are served from
/// kirana-mitra-chandra.web.app, so sign-in and data are the same.
const FirebaseOptions kiranaWebOptions = FirebaseOptions(
  apiKey: 'AIzaSyB7yaL_ifQyM5EXp6a9vcJKcDMtSp0C37w',
  appId: '1:252696167936:web:6d31cdb4f5506758ea7ae5',
  messagingSenderId: '252696167936',
  projectId: 'kirana-mitra-chandra',
  authDomain: 'kirana-mitra-chandra.firebaseapp.com',
);
