#!/usr/bin/env python3
"""
Deploy updated Firestore security rules that add the borough_announcements
collection to the existing Huddl Connect ruleset.

Uses the Firebase Rules REST API (same pattern as prior deployments in this
project).  Falls back to firebase-tools CLI if REST API is unavailable.
"""

import json
import subprocess
import sys
import os
import tempfile

# ── Config ────────────────────────────────────────────────────────────────────
PROJECT_ID = "huddl-connect"
ADMIN_SDK_PATH = "/opt/flutter/firebase-admin-sdk.json"

# ── Full ruleset — includes ALL existing collections + new borough_announcements
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

      match /savedListings/{listingId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }

    // ── Borough Announcements (Noticeboard) ───────────────────────────────
    // Shared across all users in the same borough.
    // Read: authenticated users in the same borough (verified via users doc).
    // Create: authenticated users with required string fields.
    // Update: only mutable fields (likes, likedBy, comments, pins, bookmarks, shares).
    // Delete: only the post author.
    match /borough_announcements/{docId} {
      allow read: if request.auth != null
        && resource.data.boroughId == get(/databases/$(database)/documents/users/$(request.auth.uid)).data.boroughId;
      allow create: if request.auth != null
        && request.resource.data.authorName is string
        && request.resource.data.boroughId is string;
      allow update: if request.auth != null
        && (request.resource.data.diff(resource.data).affectedKeys()
            .hasOnly(['likes','likedBy','comments','isPinned','isBookmarked','shares','commentsList']));
      allow delete: if request.auth != null
        && request.auth.uid == resource.data.authorId;
    }

    // ── DM Conversations ──────────────────────────────────────────────────
    match /conversations/{conversationId} {
      allow read, write: if request.auth != null
        && request.auth.uid in resource.data.participants;
      allow create: if request.auth != null
        && request.auth.uid in request.resource.data.participants;

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

    // ── Community Wisdom (Insights) ───────────────────────────────────────
    match /community_wisdom/{docId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null
        && resource.data.authorId == request.auth.uid;
    }

    // ── Events ────────────────────────────────────────────────────────────
    match /events/{eventId} {
      allow read: if request.auth != null;
      allow create, update: if request.auth != null;
      allow delete: if request.auth != null
        && resource.data.organiserId == request.auth.uid;
    }

    // ── Local Services ────────────────────────────────────────────────────
    match /local_services/{serviceId} {
      allow read: if request.auth != null;
      allow create, update: if request.auth != null;
      allow delete: if request.auth != null
        && resource.data.ownerId == request.auth.uid;
    }
  }
}
"""


def deploy_via_firebase_cli():
    """Try to deploy using firebase-tools CLI."""
    rules_file = "/tmp/firestore_huddl.rules"
    firebase_json = "/tmp/firebase_huddl.json"

    with open(rules_file, "w") as f:
        f.write(RULES)

    with open(firebase_json, "w") as f:
        json.dump({"firestore": {"rules": "firestore_huddl.rules"}}, f)

    print("Attempting Firebase CLI deploy...")
    result = subprocess.run(
        ["firebase", "deploy", "--only", "firestore:rules",
         "--project", PROJECT_ID],
        cwd="/tmp",
        capture_output=True,
        text=True,
        timeout=90,
    )
    if result.returncode == 0:
        print("✅ Rules deployed via Firebase CLI!")
        print(result.stdout)
        return True
    else:
        print(f"⚠️  CLI deploy failed (rc={result.returncode})")
        print(result.stderr[-800:] if result.stderr else "(no stderr)")
        return False


def deploy_via_rest_api():
    """Deploy using Firebase Rules REST API with Admin SDK credentials."""
    try:
        import google.auth
        import google.auth.transport.requests
        from google.oauth2 import service_account
        import urllib.request

        creds = service_account.Credentials.from_service_account_file(
            ADMIN_SDK_PATH,
            scopes=["https://www.googleapis.com/auth/firebase"],
        )
        auth_req = google.auth.transport.requests.Request()
        creds.refresh(auth_req)
        token = creds.token

        base = "https://firebaserules.googleapis.com/v1"
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }

        # ── Step 1: Create a new ruleset ────────────────────────────────────
        print("Creating new ruleset via REST API...")
        create_body = json.dumps({
            "source": {
                "files": [
                    {"name": "firestore.rules", "content": RULES}
                ]
            }
        }).encode()

        req = urllib.request.Request(
            f"{base}/projects/{PROJECT_ID}/rulesets",
            data=create_body,
            headers=headers,
            method="POST",
        )
        with urllib.request.urlopen(req) as resp:
            ruleset_data = json.loads(resp.read())
        ruleset_name = ruleset_data["name"]
        print(f"  New ruleset: {ruleset_name}")

        # ── Step 2: Get current cloud.firestore release ──────────────────────
        print("Fetching current release...")
        req2 = urllib.request.Request(
            f"{base}/projects/{PROJECT_ID}/releases/cloud.firestore",
            headers=headers,
            method="GET",
        )
        with urllib.request.urlopen(req2) as resp:
            release_data = json.loads(resp.read())
        release_name = release_data["name"]
        print(f"  Current release: {release_name}")

        # ── Step 3: PATCH the release to point to the new ruleset ────────────
        print("Patching release to new ruleset...")
        patch_body = json.dumps({
            "release": {
                "name": release_name,
                "rulesetName": ruleset_name,
            }
        }).encode()
        req3 = urllib.request.Request(
            f"{base}/{release_name}",
            data=patch_body,
            headers=headers,
            method="PATCH",
        )
        with urllib.request.urlopen(req3) as resp:
            patch_result = json.loads(resp.read())
        print(f"✅ Release updated: {patch_result.get('name', '(ok)')}")
        return True

    except Exception as e:
        print(f"⚠️  REST API deploy failed: {e}")
        return False


def print_manual_steps():
    print("""
╔══════════════════════════════════════════════════════════════════╗
║  MANUAL FIRESTORE RULES UPDATE                                   ║
╠══════════════════════════════════════════════════════════════════╣
║  1. Open: https://console.firebase.google.com/                  ║
║     project/huddl-connect/firestore/rules                       ║
║  2. Click "Edit rules"                                           ║
║  3. Replace the entire content with the rules printed above     ║
║  4. Click "Publish"                                              ║
╚══════════════════════════════════════════════════════════════════╝
""")


if __name__ == "__main__":
    print("=" * 60)
    print("Deploying Firestore rules — adding borough_announcements")
    print("=" * 60)
    print("\nRules to be deployed:\n")
    print(RULES)
    print("=" * 60)

    # Try CLI first, then REST API
    success = False
    try:
        success = deploy_via_firebase_cli()
    except FileNotFoundError:
        print("firebase-tools not found, trying REST API...")
    except Exception as e:
        print(f"CLI error: {e}, trying REST API...")

    if not success:
        success = deploy_via_rest_api()

    if not success:
        print_manual_steps()
        sys.exit(1)

    print("\n✅ Firestore rules deployment complete!")
    print("The borough_announcements collection is now secured.")
