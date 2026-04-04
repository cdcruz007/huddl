# Configuration Files

Place these files in this directory (DO NOT commit to Git):

1. **firebase-admin-sdk.json** — Firebase Admin SDK service account key
   - Download from: Firebase Console > Project Settings > Service Accounts > Generate new private key
   - Used by: Firebase Admin SDK (Firestore, Auth, Messaging)

2. **apple-subscription-key.p8** — Apple In-App Purchase API key
   - Download from: App Store Connect > Users and Access > Keys > In-App Purchase
   - Used by: App Store Server API v2 for receipt verification

These files should be in your `.gitignore` and deployed via environment variables or secrets management.
