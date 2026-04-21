/**
 * HUDDL — Firestore Production Purge Script
 * ==========================================
 * Deletes ALL documents from every collection so the database is clean
 * for real users. Run this once from the Firebase Console.
 *
 * HOW TO RUN:
 * 1. Go to https://console.firebase.google.com/project/huddl-connect/firestore
 * 2. Click the ">_" (Shell / Console) button at the top right — opens the
 *    Firebase Firestore emulator shell, OR
 * 3. Use the Firebase CLI:
 *      firebase firestore:delete --all-collections --project huddl-connect
 *    (requires: npm install -g firebase-tools && firebase login)
 *
 * ALTERNATIVELY — run this script in the Firebase Console browser shell:
 * 1. Open Firebase Console → Firestore
 * 2. Open your browser DevTools (F12) → Console tab
 * 3. Paste and run the script below
 *
 * Collections purged:
 *   users, groups, group_messages, meetups, marketplace,
 *   conversations, direct_messages, notifications,
 *   subscriptions, messages, feedback
 */

// ─── Helper: delete all docs in a collection in batches of 500 ───────────────
async function deleteCollection(db, collectionPath) {
  const collRef = db.collection(collectionPath);
  let deleted = 0;
  let snapshot;

  do {
    snapshot = await collRef.limit(500).get();
    if (snapshot.empty) break;

    const batch = db.batch();
    snapshot.docs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
    deleted += snapshot.docs.length;
    console.log(`  ${collectionPath}: deleted ${deleted} docs so far…`);
  } while (!snapshot.empty);

  console.log(`✅ ${collectionPath}: ${deleted} documents deleted.`);
}

// ─── Main purge ───────────────────────────────────────────────────────────────
async function purgeAllData() {
  // Firebase is already available in the Firebase Console shell as `firebase`
  // In the browser console on the Firebase Console page, use:
  const db = firebase.firestore();

  const collections = [
    'users',
    'groups',
    'group_messages',
    'meetups',
    'marketplace',
    'conversations',
    'direct_messages',
    'notifications',
    'subscriptions',
    'messages',
    'feedback',
  ];

  console.log('🔥 Starting Firestore purge for project: huddl-connect');
  console.log('⚠️  This will delete ALL documents. This cannot be undone.');
  console.log('━'.repeat(60));

  for (const col of collections) {
    await deleteCollection(db, col);
  }

  console.log('━'.repeat(60));
  console.log('🎉 Purge complete. Firestore is clean for production.');
  console.log('Real users can now start registering and their data will');
  console.log('be the only content in the database.');
}

purgeAllData().catch(console.error);
