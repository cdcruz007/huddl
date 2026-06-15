#!/usr/bin/env python3
"""
backfill_group_type.py
──────────────────────
Idempotent Admin SDK backfill: set groupType on all groups docs.

Logic:
  • isImageLocked == True  → groupType = 'resident'
  • isImageLocked == False (or missing) → groupType = 'interest'

Skips docs that already have groupType set (idempotent).

DRY_RUN = True  → prints counts only, writes nothing.
DRY_RUN = False → applies writes in batches of 400.
"""

import firebase_admin
from firebase_admin import credentials, firestore

DRY_RUN = True   # ← flip to False to apply

BATCH_SIZE = 400


def main():
    if not firebase_admin._apps:
        cred = credentials.Certificate('/opt/flutter/firebase-admin-sdk.json')
        firebase_admin.initialize_app(cred)

    db = firestore.client()
    groups_ref = db.collection('groups')

    all_docs = list(groups_ref.stream())
    print(f"Total groups docs: {len(all_docs)}")

    to_write = []
    already_set = 0
    resident_count = 0
    interest_count = 0

    for doc in all_docs:
        data = doc.to_dict()
        if data.get('groupType') is not None:
            already_set += 1
            continue

        is_locked = data.get('isImageLocked', False)
        group_type = 'resident' if is_locked else 'interest'

        if group_type == 'resident':
            resident_count += 1
        else:
            interest_count += 1

        to_write.append((doc.reference, {'groupType': group_type}))

    print(f"Already have groupType: {already_set}")
    print(f"To write — resident: {resident_count}, interest: {interest_count}, total: {len(to_write)}")

    if DRY_RUN:
        print("DRY_RUN=True — no writes performed.")
        return

    # Apply in batches
    written = 0
    for i in range(0, len(to_write), BATCH_SIZE):
        batch = db.batch()
        chunk = to_write[i:i + BATCH_SIZE]
        for ref, update in chunk:
            batch.update(ref, update)
        batch.commit()
        written += len(chunk)
        print(f"  Written {written}/{len(to_write)}")

    print(f"Done. {written} docs updated.")


if __name__ == '__main__':
    main()
