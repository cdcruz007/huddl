#!/usr/bin/env python3
"""
backfill_users_public.py
========================
One-off backfill: copies the public field set from every users/{uid} document
to the corresponding users_public/{uid} document in Firestore.

Run this AFTER syncPublicProfile is deployed (Step 1) and BEFORE the
firestore.rules lock lands (Step 4). The CF will keep users_public in sync
going forward; this script seeds it for all existing accounts.

WHY THIS SCRIPT EXISTS
----------------------
syncPublicProfile (Cloud Function) fires on future writes to users/{uid}.
It does NOT retroactively populate users_public for documents that already
exist. This script is the one-time bridge.

FIELD SET (must match syncPublicProfile's PUBLIC_FIELDS exactly)
----------------------------------------------------------------
  name, photoUrl, parentType, borough, isOnline, stagesOfLife,
  ward, wardCode, districtCode, region

Only fields present on the source doc are written (absent fields are skipped,
not written as None). This mirrors the CF's `data[field] !== undefined` guard
and avoids polluting users_public with null sentinels.

SENSITIVE FIELDS — NEVER WRITTEN TO users_public
-------------------------------------------------
  phone, email, postcode, children, dueDate, fcmToken,
  stripeCustomerId, tier, roles, isFoundingMember, isPhoneVerified
  (and any other field not in PUBLIC_FIELDS)

USAGE
-----
  # Prerequisites
  pip install firebase-admin

  # Dry run — shows count + sample of first 5 docs, writes nothing
  python3 backfill_users_public.py --sdk-key /path/to/adminsdk.json --dry-run

  # Real run
  python3 backfill_users_public.py --sdk-key /path/to/adminsdk.json

  # Credential via environment variable instead of --sdk-key flag
  export FIREBASE_ADMIN_SDK_KEY=/path/to/adminsdk.json
  python3 backfill_users_public.py --dry-run

SAFETY
------
  - Idempotent: uses set() (create-or-overwrite). Running twice is safe.
  - Batched in groups of 400 (Firestore limit is 500; 400 gives headroom).
  - Commits each batch before reading the next page — partial progress is
    preserved if the script is interrupted.
  - --dry-run flag performs zero writes.
"""

import argparse
import os
import sys

# ── Field set ────────────────────────────────────────────────────────────────
# Must match syncPublicProfile's PUBLIC_FIELDS tuple in functions/src/index.ts.
# Update both together if the public schema ever changes.
PUBLIC_FIELDS = (
    "name",
    "photoUrl",
    "parentType",
    "borough",
    "isOnline",
    "stagesOfLife",
    "ward",
    "wardCode",
    "districtCode",
    "region",
)

# Explicit deny-list for documentation purposes — belt-and-suspenders check
# that none of these ever slip into the public mirror.
SENSITIVE_FIELDS = frozenset((
    "phone", "email", "postcode", "children", "dueDate",
    "fcmToken", "stripeCustomerId", "tier", "roles",
    "isFoundingMember", "isPhoneVerified",
))

BATCH_SIZE = 400


def build_public_data(source: dict) -> dict:
    """
    Extract only PUBLIC_FIELDS from a users/{uid} document.

    Mirrors syncPublicProfile's behaviour:
      - Only copies fields that exist on the source doc.
      - Never copies sensitive fields (enforced by the allowlist, not the
        denylist — the denylist is a belt-and-suspenders assertion only).
    """
    public = {}
    for field in PUBLIC_FIELDS:
        if field in source:
            value = source[field]
            # Belt-and-suspenders: assert field is not in the sensitive set.
            # This should never trigger given we use an allowlist, but if
            # PUBLIC_FIELDS is ever accidentally edited to include a sensitive
            # field, this will catch it at runtime before any data is written.
            assert field not in SENSITIVE_FIELDS, (
                f"BUG: field '{field}' is in both PUBLIC_FIELDS and "
                f"SENSITIVE_FIELDS — fix the script before running."
            )
            public[field] = value
    return public


def main():
    parser = argparse.ArgumentParser(
        description="Backfill users_public from users in Firestore (huddl-connect)."
    )
    parser.add_argument(
        "--sdk-key",
        metavar="PATH",
        help="Path to Firebase Admin SDK service-account JSON key. "
             "Falls back to FIREBASE_ADMIN_SDK_KEY env var.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report what WOULD be written without making any Firestore writes. "
             "Prints count and a sample of the first 5 docs' public data.",
    )
    args = parser.parse_args()

    # ── Resolve credential path ───────────────────────────────────────────────
    sdk_key_path = args.sdk_key or os.environ.get("FIREBASE_ADMIN_SDK_KEY")
    if not sdk_key_path:
        print(
            "ERROR: No Admin SDK key provided.\n"
            "Pass --sdk-key /path/to/key.json or set FIREBASE_ADMIN_SDK_KEY.",
            file=sys.stderr,
        )
        sys.exit(1)
    if not os.path.isfile(sdk_key_path):
        print(
            f"ERROR: SDK key file not found: {sdk_key_path}",
            file=sys.stderr,
        )
        sys.exit(1)

    # ── Initialise Admin SDK ──────────────────────────────────────────────────
    try:
        import firebase_admin
        from firebase_admin import credentials, firestore as fs
    except ImportError:
        print(
            "ERROR: firebase-admin not installed.\n"
            "Run: pip install firebase-admin",
            file=sys.stderr,
        )
        sys.exit(1)

    cred = credentials.Certificate(sdk_key_path)
    firebase_admin.initialize_app(cred)
    db = fs.client()

    # ── Mode banner ───────────────────────────────────────────────────────────
    mode = "DRY RUN (no writes)" if args.dry_run else "LIVE RUN (writes enabled)"
    print(f"\n{'='*60}")
    print(f"  backfill_users_public.py — {mode}")
    print(f"  Public fields: {', '.join(PUBLIC_FIELDS)}")
    print(f"  Batch size:    {BATCH_SIZE}")
    print(f"{'='*60}\n")

    # ── Stream all users docs, batch-write to users_public ───────────────────
    users_ref = db.collection("users")
    public_ref = db.collection("users_public")

    total_processed = 0
    total_skipped = 0      # docs where build_public_data() returned {}
    total_written = 0
    batch_count = 0

    # Collect sample data for --dry-run preview (first 5 non-empty docs)
    dry_run_samples = []

    # Stream in pages using Firestore's built-in generator.
    # The Admin SDK streams documents lazily — no full collection load into RAM.
    current_batch = db.batch()
    current_batch_size = 0

    print("Reading users collection...")

    for doc_snapshot in users_ref.stream():
        uid = doc_snapshot.id
        source_data = doc_snapshot.to_dict() or {}
        public_data = build_public_data(source_data)

        total_processed += 1

        # Progress heartbeat every 100 docs so long runs aren't silent
        if total_processed % 100 == 0:
            print(f"  ... processed {total_processed} docs so far "
                  f"(written={total_written}, skipped={total_skipped})")

        if not public_data:
            # No public fields present on this doc at all — skip.
            # This can happen for partially-created accounts.
            total_skipped += 1
            print(f"  SKIP uid={uid} — no public fields present on source doc")
            continue

        if args.dry_run:
            # Collect sample for preview; don't add to batch
            if len(dry_run_samples) < 5:
                dry_run_samples.append((uid, public_data))
            total_written += 1  # count what WOULD be written
            continue

        # Queue in current batch
        doc_ref = public_ref.document(uid)
        current_batch.set(doc_ref, public_data)
        current_batch_size += 1
        total_written += 1

        # Commit when batch is full
        if current_batch_size >= BATCH_SIZE:
            batch_count += 1
            print(f"  Committing batch {batch_count} "
                  f"({current_batch_size} writes)...")
            current_batch.commit()
            print(f"  Batch {batch_count} committed.")
            current_batch = db.batch()
            current_batch_size = 0

    # Commit any remaining docs in the final partial batch
    if not args.dry_run and current_batch_size > 0:
        batch_count += 1
        print(f"  Committing final batch {batch_count} "
              f"({current_batch_size} writes)...")
        current_batch.commit()
        print(f"  Final batch {batch_count} committed.")

    # ── Summary ───────────────────────────────────────────────────────────────
    print(f"\n{'='*60}")
    if args.dry_run:
        print(f"  DRY RUN COMPLETE — no writes made")
        print(f"  Would process: {total_processed} users docs")
        print(f"  Would write:   {total_written} users_public docs")
        print(f"  Would skip:    {total_skipped} docs (no public fields)")
        if dry_run_samples:
            print(f"\n  Sample public data (first {len(dry_run_samples)} non-empty docs):")
            for uid, data in dry_run_samples:
                print(f"\n  uid={uid}")
                for k, v in data.items():
                    print(f"    {k}: {repr(v)}")
        else:
            print("\n  No docs with public fields found — check users collection.")
    else:
        print(f"  BACKFILL COMPLETE")
        print(f"  Docs processed:        {total_processed}")
        print(f"  users_public written:  {total_written}")
        print(f"  Skipped (no pub flds): {total_skipped}")
        print(f"  Batches committed:     {batch_count}")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    main()
