#!/usr/bin/env python3
"""
backfill_birth_year.py
──────────────────────
Idempotent Admin SDK backfill: populate birthYear on resident group docs.

Logic:
  • Only processes docs where groupType == 'resident' (or isImageLocked == True
    as a fallback for un-backfilled-type docs).
  • Skips docs that already have birthYear set (idempotent).
  • Extracts the leading 4-digit year from the group name using the same
    regex pattern as DefaultGroupService (e.g. "2019 Cambridge Parents" → 2019).
  • Docs with no parseable year in the name → skipped (no fabrication).

DRY_RUN = True  → prints counts only, writes nothing.
DRY_RUN = False → applies writes in batches of 400.
"""

import re
import firebase_admin
from firebase_admin import credentials, firestore

DRY_RUN = True   # ← flip to False to apply

BATCH_SIZE = 400
YEAR_RE = re.compile(r'^(\d{4})\s+\S')


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
    not_resident = 0
    no_year_in_name = 0

    for doc in all_docs:
        data = doc.to_dict()

        # Idempotent: skip if already set
        if data.get('birthYear') is not None:
            already_set += 1
            continue

        # Only resident groups get a birthYear
        group_type = data.get('groupType')
        is_locked = data.get('isImageLocked', False)
        if group_type != 'resident' and not is_locked:
            not_resident += 1
            continue

        # Extract year from name
        name = data.get('name', '')
        m = YEAR_RE.match(name)
        if not m:
            no_year_in_name += 1
            continue

        birth_year = int(m.group(1))
        to_write.append((doc.reference, {'birthYear': birth_year}))

    print(f"Already have birthYear:             {already_set}")
    print(f"Not resident (skipped):             {not_resident}")
    print(f"Resident but no year in name (skip):{no_year_in_name}")
    print(f"To write:                           {len(to_write)}")

    if DRY_RUN:
        print("DRY_RUN=True — no writes performed.")
        return

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
