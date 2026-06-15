#!/usr/bin/env python3
"""
backfill_geo_stack.py
─────────────────────
Idempotent Admin SDK backfill: populate ward/wardCode/districtCode/region
on users and groups docs that have a postcode but are missing geo fields.

Logic:
  • For each users doc with a non-empty 'postcode' and at least one missing
    geo field (ward/wardCode/districtCode/region), call postcodes.io.
  • Same for groups docs.
  • Docs with no postcode → skip (no fabrication).
  • Docs that already have all four geo fields → skip (idempotent).
  • postcodes.io returns null for some fields (e.g. admin_ward in Scotland)
    → only write non-null values.

DRY_RUN = True  → prints counts only, writes nothing.
DRY_RUN = False → applies writes (one Firestore update per doc with non-null
                  geo fields) in batches of 400.

Rate limiting: 100ms sleep between each unique postcodes.io call to stay
within the free tier (1 req/sec sustained, burst to 10 req/sec).
"""

import time
import json
import urllib.request
import urllib.parse
import firebase_admin
from firebase_admin import credentials, firestore

DRY_RUN = True       # ← flip to False to apply
BATCH_SIZE = 400
GEO_FIELDS = ('ward', 'wardCode', 'districtCode', 'region')


def lookup_geo(postcode: str) -> dict:
    """
    Call postcodes.io for a single postcode.
    Returns a dict with keys: ward, wardCode, districtCode, region.
    Values may be None if the API doesn't return them.
    Returns empty dict on network error or 404.
    """
    clean = postcode.replace(' ', '').upper()
    url = f'https://api.postcodes.io/postcodes/{urllib.parse.quote(clean)}'
    try:
        with urllib.request.urlopen(url, timeout=8) as resp:
            if resp.status != 200:
                return {}
            data = json.loads(resp.read().decode('utf-8'))
            result = data.get('result') or {}
            codes = result.get('codes') or {}
            return {
                'ward':         result.get('admin_ward'),
                'wardCode':     codes.get('admin_ward'),
                'districtCode': codes.get('admin_district'),
                'region':       result.get('region'),
            }
    except Exception as e:
        print(f"  postcodes.io error for {clean}: {e}")
        return {}


def needs_geo(data: dict) -> bool:
    return any(data.get(f) is None for f in GEO_FIELDS)


def process_collection(db, collection_name: str, postcode_cache: dict, to_write: list):
    ref = db.collection(collection_name)
    docs = list(ref.stream())
    print(f"\n{collection_name}: {len(docs)} docs total")

    no_postcode = 0
    already_complete = 0
    to_resolve = 0
    api_errors = 0
    will_write = 0

    for doc in docs:
        data = doc.to_dict()
        postcode = (data.get('postcode') or '').strip()
        if not postcode:
            no_postcode += 1
            continue
        if not needs_geo(data):
            already_complete += 1
            continue

        to_resolve += 1
        if postcode not in postcode_cache:
            time.sleep(0.1)  # stay within postcodes.io rate limit
            postcode_cache[postcode] = lookup_geo(postcode)

        geo = postcode_cache[postcode]
        if not geo:
            api_errors += 1
            continue

        # Only write non-None values
        update = {k: v for k, v in geo.items() if v is not None}
        if update:
            to_write.append((doc.reference, update))
            will_write += 1

    print(f"  no postcode:       {no_postcode}")
    print(f"  already complete:  {already_complete}")
    print(f"  to resolve:        {to_resolve}")
    print(f"  api errors:        {api_errors}")
    print(f"  will write:        {will_write}")


def main():
    if not firebase_admin._apps:
        cred = credentials.Certificate('/opt/flutter/firebase-admin-sdk.json')
        firebase_admin.initialize_app(cred)

    db = firestore.client()
    to_write = []
    postcode_cache = {}  # shared across collections — avoids re-calling API for same postcode

    process_collection(db, 'users', postcode_cache, to_write)
    process_collection(db, 'groups', postcode_cache, to_write)

    print(f"\nTotal docs to write: {len(to_write)}")

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
