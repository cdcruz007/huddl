#!/usr/bin/env python3
"""
set_admin_role.py
=================
Sets roles.isAdmin = True on a Huddl user's Firestore document so they can
access the Admin Dashboard (Report Dashboard) inside the app.

USAGE
-----
Method A — Firebase Admin SDK (recommended if you have the key):
  1. Download the Admin SDK key from Firebase Console →
     Project Settings → Service accounts → Generate new private key
  2. pip install firebase-admin
  3. python3 set_admin_role.py --sdk-key /path/to/adminsdk.json --uid <USER_UID>

Method B — Manual (no SDK key needed):
  1. Find the user UID in Firebase Console → Authentication → Users
     Search for +447575888452 (Conrad's phone number)
  2. Go to Firestore Console:
     https://console.firebase.google.com/project/huddl-connect/firestore/data/users/<UID>
  3. Edit the document — add/update field:
     Field: roles        Type: map
       └ isAdmin        Type: boolean    Value: true

PROJECT INFO
------------
  Firebase project: huddl-connect (879152141283)
  Firestore path:   users/{uid}/roles.isAdmin = true
  Auth lookup:      Firebase Console → Authentication → Users → search +447575888452
"""

import sys
import argparse

def set_admin_via_sdk(sdk_key_path: str, uid: str):
    try:
        import firebase_admin
        from firebase_admin import credentials, firestore
    except ImportError:
        print("❌ firebase-admin not installed. Run: pip install firebase-admin==7.1.0")
        sys.exit(1)

    print(f"🔑 Initialising Firebase Admin SDK from {sdk_key_path} ...")
    cred = credentials.Certificate(sdk_key_path)
    firebase_admin.initialize_app(cred)

    db = firestore.client()
    user_ref = db.collection('users').document(uid)

    # Check the document exists first
    doc = user_ref.get()
    if not doc.exists:
        print(f"❌ No Firestore document found for UID: {uid}")
        print("   Make sure the user has logged in at least once so their document is created.")
        sys.exit(1)

    existing = doc.to_dict()
    print(f"✅ Found user document. Name: {existing.get('name', '(no name field)')}")

    # Merge-update the roles map so other role fields are preserved
    user_ref.set({'roles': {'isAdmin': True}}, merge=True)
    print(f"✅ Set roles.isAdmin = true for UID: {uid}")
    print()
    print("The 'Admin Dashboard' / 'Review user reports' button will now appear")
    print("in Conrad's Profile screen after the next app launch or profile refresh.")


def print_manual_instructions():
    print("""
=======================================================================
  MANUAL SETUP — No Admin SDK key needed
=======================================================================

Step 1: Find Conrad's UID
─────────────────────────
  1. Open: https://console.firebase.google.com/project/huddl-connect/authentication/users
  2. Search for: +447575888452
  3. Copy the UID (looks like: abc123XYZ...)

Step 2: Set roles.isAdmin in Firestore
────────────────────────────────────────
  1. Open: https://console.firebase.google.com/project/huddl-connect/firestore/data/users/<PASTE_UID_HERE>
  2. Click "+ Add field" or click the "roles" map if it already exists
  3. Add/update:
       Field name: roles        (type: map)
         ↳ Field: isAdmin       (type: boolean)   Value: ✓ (true)
  4. Click Update

Step 3: Verify
──────────────
  Conrad opens the app → Profile tab → scroll to the account/settings section
  → "Admin Dashboard" / "Review user reports" button appears (shield icon)
  → Tap it → Report Dashboard loads with Pending / Reviewed / Actioned / Dismissed filter tabs

=======================================================================
""")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Grant Huddl admin role to a user')
    parser.add_argument('--sdk-key', help='Path to Firebase Admin SDK JSON key file')
    parser.add_argument('--uid', help='Firebase UID of the user to make admin')
    args = parser.parse_args()

    if args.sdk_key and args.uid:
        set_admin_via_sdk(args.sdk_key, args.uid)
    else:
        print_manual_instructions()
