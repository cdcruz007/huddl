#!/usr/bin/env python3
"""
fix_broken_images.py
Fixes only the 16 broken/missing imageUrl entries in local_services Firestore collection.
Fresh images sourced via image_search tool — all sspark.genspark.ai/cfimages proxy URLs.
"""

import firebase_admin
from firebase_admin import credentials, firestore

if not firebase_admin._apps:
    cred = credentials.Certificate('/opt/flutter/firebase-admin-sdk.json')
    firebase_admin.initialize_app(cred)

db = firestore.client()

# ─────────────────────────────────────────────────────────────────────────────
# ONLY the 16 broken/missing listings — fresh URLs from new image_search calls
# ─────────────────────────────────────────────────────────────────────────────
FIX_IMAGES = {

    # ── FITNESS ──────────────────────────────────────────────────────────────
    # Buggy Bootcamp Cambridge  (was HTTP 403)
    "6O0jtROufkSVfAxWwh6E": "https://sspark.genspark.ai/cfimages?u1=zv1cEYT73EoF9zbeB2jWZA65IIuBFgMp1NenDWkmmmHsFi5QHp2cktDYsNnEJSh7AUAniMgdgwGJ%2FJEpzMliQyFq72PrAncaoefVigk%2ByVaN2WXMEv5TRkoYAFLfGpAyciqhxfMbd0jUIg4teQNbMI%2BqVad4pA%3D%3D&u2=8FI0ifCXT%2FyFCWbj&width=2560",

    # ParkRun Cambridge — Family Mile  (was MISSING)
    "FjopesaM1AnAllyL5OAw": "https://sspark.genspark.ai/cfimages?u1=3NxP1sC6KNKrQ5ckiOZHk2%2BgN2B6aOtE6CJ7Ut1k44xAOGKv3KLlpNRiDkjFHua8Ae%2BDfU7xHSWmx9YmsbXE5eom3ycYnCFXb2TrxrrVsxgu4z0QubbE%2Bf60AmhCSajtaA%3D%3D&u2=uH8ELkL9B19XbGm4&width=2560",

    # ── FOOD ─────────────────────────────────────────────────────────────────
    # The Feeding Room Cambridge  (was HTTP 400)
    "DUt0vgtkK2rrZS0e4fni": "https://sspark.genspark.ai/cfimages?u1=Nu10VNO0mQPl0H%2FUGBHtftSRh4Kck%2F4w%2BuCrSvGc7Xd4okXW1TDuhFtG0bRIc%2FfjuyOcpuJ0i660Q0tJ9GV1S5ACqy0VVcgv45xXx1TjGikSmYXu8QNgs0ODK34gIsf52npclcuSvGOiybwRgRrK00VHg068JpOCUKOI%2B5cN46UzB%2FIm%2FAuRj7sBossIppOVl6mtjzKu0Y8xTl8DSvPWbp37F4jJXNayFYNX4LHoLHqotttBYTs%3D&u2=btGxJfTMtj7X89Vg&width=2560",

    # NCT Cambridge Bumps & Babies Café  (was HTTP 403)
    "N5ZNWcvRaWXC0utKOhef": "https://sspark.genspark.ai/cfimages?u1=9qUyMOI8ERcCPygD4jMlvCOy4RN0HFMaPoFBzKkXJrSDSGgdG3XkSyCQUbnD9ITbi1zFMCcWhHs6EyCTj4ZZoxhY8csGG7pUAvr8UEehV4hcGuWOZ4Dv0GGNjKM%3D&u2=LOVQEwLeD6XGFYrJ&width=2560",

    # ── CLEANING ─────────────────────────────────────────────────────────────
    # Hannah's Home Cleans  (was HTTP 400)
    "MLauYSKh8bX0DuHyxNHD": "https://sspark.genspark.ai/cfimages?u1=%2BKGUwI5qIg7qHBDD%2B8CDJqX8EnibiynThVwSVKV339Lqvq%2BgwIb2v5Sr8VUIfdt63tGPQWJOvDHxw2dxksg%2BZ2ajDq38519MUcP8ECTn25GExg%3D%3D&u2=nwOlvk1H8YCoKloc&width=2560",

    # ── HOME SERVICES ────────────────────────────────────────────────────────
    # Cambridge Plumbing Plus  (was HTTP 400)
    "HRhwetIrT9f9q6ig1MjI": "https://sspark.genspark.ai/cfimages?u1=%2FoElSuyf4%2B%2BbcfaQeLwQrmMNh3%2FJ2h%2FHxNG8WrgfM8VVpmr6i8Ebf1iWWY%2BMLLlbXd%2By1g%2FM7GVOqZFQpgy6uI9wgbbfHOmBaHnnup4W49MUUqym9e0J7AsbJRxWCbeQZpGoMKOnAVphGi8p1MDiG6voeyrFY1731At%2FYDPumSPueWIJqK6dXvxP%2FV7bQ2mIpxTrQVMTzZMfdCHbn1FRC8ISrwe6zYWo&u2=3xbcvYUfJkZeVK0G&width=2560",

    # EcoNest Builders Cambridge  (was HTTP 530)
    "NfhgcNEw7taybsMRAgqL": "https://sspark.genspark.ai/cfimages?u1=SzQwgkvsKZChis1DFJ8mqPfpeoUuh27Ekje%2BJraVzdpwSvvWmmGRoZYwYmmhfJF3KZ3WnPFYD7yhm09VrhAhMEoqQzUHA1vycMW6DcLqjMP%2FvkG5nRCvCb%2B7Uw%3D%3D&u2=PH0hJjeTNiVyMsiw&width=2560",

    # Bright Spark Electrical — Cambridge  (was HTTP 400)
    "qubLqK16iVDXLwdxTCh5": "https://sspark.genspark.ai/cfimages?u1=0A2o%2FWszdFtw76fWDRLo4mxy1z%2B%2BF4TXDIF%2B%2FBMPeMjEDITe1Illh%2BkL3CTD188l5C1xUzbqpilhmbHJbLcGlr7aZ5UzU1rm6b1mrtPeJ2X7lEGTq%2Bxg%2BflbKzXTLc%2FvhkvJzSFIGi2a05jaimrpzSq8urpEsj1ClyBb17V20OkEe90Y7s1rj7d1gfT3jXccpsZV1Q0AdFYC2yglzgoCqCHZvNiUwZqtnOg%2Bhkg%3D&u2=EeuUw6Od21wye6N8&width=2560",

    # ── PHOTOGRAPHY ──────────────────────────────────────────────────────────
    # Cambridge Baby & Family Photography  (was HTTP 403)
    "SJ5Sd0UFOiSgj4MMe9YA": "https://sspark.genspark.ai/cfimages?u1=tSnYuZ0%2FZBH99Yi71jkeslmlBuCO8JNzbGx6YW3O7XXFN1KlnMPyC1A%2FMlBFmt6GTQhdBv1MO%2F52UyIQGNkNLs1BX9YpQlEGRbqZj4ke%2FLXt3Czcsh7eeduLwqIucjAq6jswOkxTBKeSRl%2FEQDaLMQ%3D%3D&u2=sAdGh47nboWeTHe5&width=2560",

    # ── CHILDCARE ────────────────────────────────────────────────────────────
    # Fen Ditton Tots Childcare  (was HTTP 400)
    "eANNoE0O7XQI5717Mvuz": "https://sspark.genspark.ai/cfimages?u1=vvpuu4fxcCh%2F2P6GC9ZVw0eSAJQN6nnLJ2YZROvppLjxFNixe5Id8LjI9BNiZDgm4KhOqzBjf%2Fh4ETocGLSdiWgS%2B7RhH6Sy9uXq3TKSPZnzHGR8i%2Bk0cx%2Bwr9c2gw3wx4vepGMBiqxoahiw9dQtZnTEVE3EdMuCtZK8D%2FrwU5AxL7%2Fo47N0CQ8wezk0tDYn8KYSyo2pu1Xo1Zozul76rKNvT2Wc0WfrYrYsy5zhBM%2Bryh9pa%2F5sAgKy4w%2FJiRU%2B3gGRFGWQZSMw8As%3D&u2=BhCAnYALcyZ1r%2BVK&width=2560",

    # ── OTHER ────────────────────────────────────────────────────────────────
    # Home Start Cambridge  (was HTTP 400)
    "h4PZPTuIkvBVT13mBdQu": "https://sspark.genspark.ai/cfimages?u1=YwuH4bwGuq6eMge%2B2w0x89dEq%2B6gXho4P%2Flckh%2F09SeSjZUdIIe7qjcWgffn4FsnifRTlXZwnCg5gW2OCK9Gpbeb5rp%2FhVfck1mMpSfOpbZ9vWAOZZRfcf6mMCLDVPBalnvIPru0Xg%3D%3D&u2=N1R6y0y7ETGq2d7g&width=2560",

    # Cambridge NCT — Antenatal Courses  (was HTTP 403)
    "o5Ota32TwWxOQVc9GbVA": "https://sspark.genspark.ai/cfimages?u1=Uv9hHVx6p411IUl4tVyV2kp308wZsl6BhfobWFSOxfjIrV9OCOd4%2FBIlHcpDGLL1FoPkDYUA%2FnqiBe6LZqDG%2B9Iq5OuJwmL7H8GrQlH%2BXreq%2FOTQqoWF95lDcL3dnuMUVg%3D%3D&u2=2dHswqnw%2FFl9LTTm&width=2560",

    # ── HEALTH & WELLNESS ────────────────────────────────────────────────────
    # ABC Audiology — Cambridge  (was HTTP 502)
    "hsjS6myuzGv3JvjWSKj8": "https://sspark.genspark.ai/cfimages?u1=k%2BQ7Fe924QVVLSGEOFf9zc9q7yGw%2BPsvghZ72AVSel9vj3tellGurdUBEtWRX8b1ZIjPl0nIa3A2j7HDrooU7ysxCX8fWMsV%2B%2FYrQ9ml%2FGwoV3wQc06Rz6P52B5YhC3tsQklzmu9FsxTHw%3D%3D&u2=fUmfDN8VosqjmoXu&width=2560",

    # ── FIRST AID ────────────────────────────────────────────────────────────
    # Cambridge First Aid Training  (was HTTP 502)
    "n2aSf1rtlSKthO4OCALd": "https://sspark.genspark.ai/cfimages?u1=fEDtEGPn60W4%2Fqm84IAa%2FzTbaAFbEO3d3ZERUuibhtUP%2Bu1FQnZ1ol7deegb7haEy%2BYzrWMp6bayuzDLrAJnpF7lyeibGcZ2n%2FLmulv1WZxYMa35SjuxDFwWGyZscF5o%2FEdhgjbdOJlVugvqu9EFyJmM&u2=SmvczqyxbKPwQxQT&width=2560",

    # ── DOULA ────────────────────────────────────────────────────────────────
    # Sarah Webb — Postnatal Doula  (was HTTP 400)
    "vbyei01CZV7wAMUapkh8": "https://sspark.genspark.ai/cfimages?u1=M9PQ6Afrsovnakx5WsUYG%2FkLiG4bRYSafIu6ZAqPkHZcbKkRu%2FCyl8gxsgH4Bi9OIRHA5aTX%2Bz5yAmL51%2FNG5jykO4X7elYcWc0Zyj7jBN8gxcwB3Tv%2F0Mikf%2Fbk&u2=eVd%2FV0VXGxT74bGa&width=2560",

    # ── EMPTY DOC ────────────────────────────────────────────────────────────
    # unknown / empty doc — skip (no name, no category) handled below
    # "sT8KUvedrcpxmYj69eR9": skip
}


def main():
    print("=" * 60)
    print("Fixing broken/missing imageUrl fields — targeted patch")
    print(f"Total docs to fix: {len(FIX_IMAGES)}")
    print("=" * 60)

    updated = 0
    skipped = 0
    errors = 0

    for doc_id, image_url in FIX_IMAGES.items():
        try:
            doc_ref = db.collection('local_services').document(doc_id)
            doc = doc_ref.get()

            if not doc.exists:
                print(f"  ⚠️  Doc not found: {doc_id}")
                skipped += 1
                continue

            name = doc.to_dict().get('name', doc_id)
            doc_ref.update({'imageUrl': image_url})
            print(f"  ✅  {name[:55]}")
            updated += 1

        except Exception as e:
            print(f"  ❌  {doc_id}: {e}")
            errors += 1

    print()
    print("=" * 60)
    print(f"Results: {updated} updated, {skipped} skipped, {errors} errors")
    print("=" * 60)


if __name__ == '__main__':
    main()
