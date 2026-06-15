#!/usr/bin/env python3
"""
backfill_group_level.py
────────────────────────
Idempotent Admin SDK backfill for Stage 3a-prereq.  Does two things in a
single pass over the groups collection:

  1. level = 'borough'
     Every resident group doc that is missing the 'level' field gets
     level = 'borough'.  (Ward- and region-level groups do not exist yet,
     so every resident group is by definition borough-level.)

     Resident = groupType == 'resident'  OR  (groupType is None AND isImageLocked == True)
     Interest groups (groupType == 'interest' / isImageLocked == False) are skipped.

  2. parentRegionName  (copy of the existing 'region' geo field)
     Borough-level resident docs that already have a non-empty 'region' field
     but are missing 'parentRegionName' get:
         parentRegionName = <value of region field>

     This gives borough docs a stable FK string (parentRegionName) that can be
     used to locate the region-level group without relying on naming convention
     alone.

── RUNBOOK DEPENDENCY ────────────────────────────────────────────────────────
  Run backfill_geo_stack.py FIRST.
  Borough docs whose 'region' field is empty (geo was never resolved or geo
  backfill has not yet run) will receive level='borough' but NO parentRegionName.
  Those groups cannot be rolled up to a region group until:
    (a) backfill_geo_stack.py populates their 'region' field, AND
    (b) this script is re-run to copy region → parentRegionName.
  This is acceptable: region rollup for those groups is deferred, not broken.
──────────────────────────────────────────────────────────────────────────────

Skips docs that already have BOTH 'level' AND 'parentRegionName' set
(or are not resident groups).  Safe to re-run after ward/region groups exist
— those already have 'level' set so they are skipped.

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
    print()

    # ── Categorise docs ──────────────────────────────────────────────────────
    skipped_not_resident    = 0   # interest groups — skip entirely
    already_complete        = 0   # have both level + parentRegionName (or no region to copy)

    need_level_only         = 0   # missing level, region is empty/absent
    need_level_and_prn      = 0   # missing level, region is present → write both
    need_prn_only           = 0   # already has level, missing parentRegionName, region present

    to_write = []   # list of (ref, update_dict)

    for doc in all_docs:
        data = doc.to_dict()

        # ── Classify: resident or not ────────────────────────────────────────
        group_type = data.get('groupType')
        is_locked  = data.get('isImageLocked', False)
        is_resident = (group_type == 'resident') or \
                      (group_type is None and is_locked is True)

        if not is_resident:
            skipped_not_resident += 1
            continue

        has_level = data.get('level') is not None
        has_prn   = data.get('parentRegionName') is not None
        region    = data.get('region', '')
        region_present = isinstance(region, str) and region.strip() != ''

        # ── Determine what (if anything) needs writing ───────────────────────
        update = {}

        if not has_level:
            update['level'] = 'borough'

        if not has_prn and region_present:
            update['parentRegionName'] = region.strip()

        if not update:
            already_complete += 1
            continue

        # Tally for the dry-run summary
        wrote_level = 'level' in update
        wrote_prn   = 'parentRegionName' in update

        if wrote_level and wrote_prn:
            need_level_and_prn += 1
        elif wrote_level:
            need_level_only += 1
        else:
            need_prn_only += 1

        to_write.append((doc.reference, update))

    # ── Dry-run report ────────────────────────────────────────────────────────
    print("── Classification ──────────────────────────────────────────────")
    print(f"  Skipped (not resident / interest):         {skipped_not_resident}")
    print(f"  Already complete (no writes needed):       {already_complete}")
    print()
    print("── To write ────────────────────────────────────────────────────")
    print(f"  level='borough' only (region absent):      {need_level_only}")
    print(f"  level='borough' + parentRegionName:        {need_level_and_prn}")
    print(f"  parentRegionName only (level already set): {need_prn_only}")
    print(f"  Total docs to update:                      {len(to_write)}")
    print()

    if DRY_RUN:
        print("DRY_RUN=True — no writes performed.")
        print()
        print("── Runbook note ────────────────────────────────────────────────")
        print("  Run backfill_geo_stack.py BEFORE this script.")
        print("  Docs with 'level only' (no region) cannot roll up to a region")
        print("  group until geo is backfilled and this script is re-run.")
        return

    # ── Apply in batches ──────────────────────────────────────────────────────
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
