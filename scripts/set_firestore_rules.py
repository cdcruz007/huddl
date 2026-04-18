#!/usr/bin/env python3
"""
Set Firestore security rules for Huddl Connect.

Rules summary:
- users collection: any authenticated user can read all users (needed for
  borough-member discovery). Only the document owner can write their own profile.
- conversations collection: participants can read/write their own conversations.
  Sub-collection messages: same participants restriction.
- All other collections: require auth (existing app behaviour).
"""

import subprocess
import sys
import json
import os

PROJECT_ID = "huddl-connect"

RULES = """rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // ── Users ─────────────────────────────────────────────────────────────
    // Any authenticated user can read user profiles (needed for borough
    // member discovery in the New DM screen and matchmaker).
    // Only the profile owner can write their own document.
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }

    // ── DM Conversations ──────────────────────────────────────────────────
    // Participants can read and write the conversation document.
    match /conversations/{conversationId} {
      allow read, write: if request.auth != null
        && request.auth.uid in resource.data.participants;

      // Allow creation of new conversations by any authenticated user
      allow create: if request.auth != null
        && request.auth.uid in request.resource.data.participants;

      // ── Messages sub-collection ──────────────────────────────────────
      match /messages/{messageId} {
        allow read: if request.auth != null
          && request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participants;
        allow create: if request.auth != null
          && request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participants
          && request.resource.data.senderId == request.auth.uid;
        allow update: if request.auth != null
          && request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participants;
        allow delete: if false;
      }
    }

    // ── Groups ────────────────────────────────────────────────────────────
    match /groups/{groupId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null
        && (request.auth.uid in resource.data.memberIds
            || request.auth.uid == resource.data.creatorId);
      allow create: if request.auth != null;

      match /messages/{messageId} {
        allow read: if request.auth != null;
        allow create: if request.auth != null
          && request.resource.data.senderId == request.auth.uid;
        allow update: if request.auth != null;
        allow delete: if false;
      }
    }

    // ── Subscriptions ─────────────────────────────────────────────────────
    match /subscriptions/{subId} {
      allow read, write: if request.auth != null
        && (resource == null || resource.data.userId == request.auth.uid);
      allow create: if request.auth != null
        && request.resource.data.userId == request.auth.uid;
    }

    // ── Notifications ─────────────────────────────────────────────────────
    match /notifications/{notifId} {
      allow read, update: if request.auth != null
        && resource.data.userId == request.auth.uid;
      allow create: if request.auth != null;
      allow delete: if false;
    }

    // ── Meetups ───────────────────────────────────────────────────────────
    match /meetups/{meetupId} {
      allow read: if request.auth != null;
      allow create, update: if request.auth != null;
      allow delete: if request.auth != null
        && resource.data.organiserId == request.auth.uid;
    }

    // ── Marketplace ───────────────────────────────────────────────────────
    match /marketplace/{itemId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null
        && resource.data.sellerId == request.auth.uid;
    }

    // ── Direct Messages (legacy flat collection) ──────────────────────────
    match /direct_messages/{msgId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null
        && request.resource.data.senderId == request.auth.uid;
      allow update: if request.auth != null;
      allow delete: if false;
    }
  }
}
"""

def set_rules():
    # Write rules to a temp file
    rules_file = "/tmp/firestore.rules"
    with open(rules_file, "w") as f:
        f.write(RULES)
    print(f"Rules written to {rules_file}")
    print("\nFirestore Security Rules:")
    print("=" * 60)
    print(RULES)
    print("=" * 60)

    # Try to deploy using firebase-tools if available
    try:
        # Write firebase.json
        firebase_config = {
            "firestore": {
                "rules": "firestore.rules"
            }
        }
        with open("/tmp/firebase.json", "w") as f:
            json.dump(firebase_config, f)

        # Copy rules to project dir
        import shutil
        shutil.copy(rules_file, "/tmp/firestore.rules")

        result = subprocess.run(
            ["firebase", "deploy", "--only", "firestore:rules",
             "--project", PROJECT_ID],
            cwd="/tmp",
            capture_output=True,
            text=True,
            timeout=60
        )
        if result.returncode == 0:
            print("✅ Firestore rules deployed successfully via Firebase CLI!")
        else:
            print(f"⚠️  Firebase CLI deploy failed: {result.stderr}")
            print("📋 Manual steps to set rules:")
            _print_manual_steps()
    except FileNotFoundError:
        print("⚠️  firebase-tools not installed")
        print("📋 Manual steps to set rules:")
        _print_manual_steps()
    except Exception as e:
        print(f"⚠️  Error deploying rules: {e}")
        _print_manual_steps()

def _print_manual_steps():
    print("""
MANUAL SETUP STEPS:
1. Open Firebase Console: https://console.firebase.google.com/project/huddl-connect/firestore/rules
2. Click 'Edit rules'
3. Replace the contents with the rules printed above
4. Click 'Publish'
""")

if __name__ == "__main__":
    set_rules()
