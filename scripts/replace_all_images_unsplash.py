"""
Replace all 64 local_services imageUrl fields with stable Unsplash direct CDN URLs.
Each URL is hand-matched to the specific listing's category and nature.
Unsplash CDN URLs (images.unsplash.com) are permanent and never expire.
"""

import firebase_admin
from firebase_admin import credentials, firestore
import urllib.request
import time

cred = credentials.Certificate("/opt/flutter/firebase-admin-sdk.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

# ─────────────────────────────────────────────────────────────────────────────
# NAME → STABLE UNSPLASH URL
# Chosen to match each listing's actual service type.
# Format: w=400&q=80 keeps file size small for mobile cards.
# ─────────────────────────────────────────────────────────────────────────────
IMAGE_MAP = {
    # ── healthWellness ────────────────────────────────────────────────────────
    "Cambridge Osteopathic Practice":
        "https://images.unsplash.com/photo-1576091160550-2173dba999ef?w=400&q=80",
    "Cambridge Acupuncture & Wellness":
        "https://images.unsplash.com/photo-1512290923902-8a9f81dc236c?w=400&q=80",
    "The Bump & Baby Clinic":
        "https://images.unsplash.com/photo-1560253023-3ec5d502959f?w=400&q=80",
    "Weaning Workshop Cambridge":
        "https://images.unsplash.com/photo-1590779033100-9f60a05a013d?w=400&q=80",
    "Cambridge Postnatal Pilates":
        "https://images.unsplash.com/photo-1518611012118-696072aa579a?w=400&q=80",
    "Cambridge Pregnancy Yoga":
        "https://images.unsplash.com/photo-1545205597-3d9d02c29597?w=400&q=80",
    "Little Lungs — Paediatric Physio":
        "https://images.unsplash.com/photo-1579684385127-1ef15d508118?w=400&q=80",
    "ABC Audiology — Cambridge":
        "https://images.unsplash.com/photo-1559757175-0eb30cd8c063?w=400&q=80",
    "Cambridge Sleep Consultants":
        "https://images.unsplash.com/photo-1540655037529-dec987208707?w=400&q=80",

    # ── cleaning ─────────────────────────────────────────────────────────────
    "Merry Maids Cambridge":
        "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=400&q=80",
    "Hannah's Home Cleans":
        "https://images.unsplash.com/photo-1581578731548-c64695cc6952?w=400&q=80",
    "Cambridge Clean Team":
        "https://images.unsplash.com/photo-1556911220-bff31c812dba?w=400&q=80",
    "Pristine Cambridge":
        "https://images.unsplash.com/photo-1584820927498-cfe5211fd8bf?w=400&q=80",
    "Spotless Cambridge":
        "https://images.unsplash.com/photo-1563453392212-326f5e854473?w=400&q=80",

    # ── education ────────────────────────────────────────────────────────────
    "Little Coders Cambridge":
        "https://images.unsplash.com/photo-1587440871875-191322ee64b0?w=400&q=80",
    "Cambridge Tutors — Primary & SEND":
        "https://images.unsplash.com/photo-1503676260728-1c00da094a0b?w=400&q=80",
    "Harmony Music School Cambridge":
        "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=400&q=80",
    "Stories & Stars — Reading Club":
        "https://images.unsplash.com/photo-1456513080510-7bf3a84b82f8?w=400&q=80",
    "Mathletics Cambridge":
        "https://images.unsplash.com/photo-1509228468518-180dd4864904?w=400&q=80",
    "Cambridge Language School — Young Learners":
        "https://images.unsplash.com/photo-1488190211105-8b0e65b80b4e?w=400&q=80",
    "Cambridge Supernanny — Parenting Support":
        "https://images.unsplash.com/photo-1536640712-4d4c36ff0e4e?w=400&q=80",

    # ── photography ──────────────────────────────────────────────────────────
    "Little Moments Photography":
        "https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=400&q=80",
    "Golden Hour Photography":
        "https://images.unsplash.com/photo-1452587925148-ce544e77e70d?w=400&q=80",
    "Pixie Photography Cambridge":
        "https://images.unsplash.com/photo-1502982720700-bfff97f2ecac?w=400&q=80",
    "Cambridge College Portraits":
        "https://images.unsplash.com/photo-1551817958-20204d6ab212?w=400&q=80",
    "Cambridge Baby & Family Photography":
        "https://images.unsplash.com/photo-1491013516836-7db643ee125a?w=400&q=80",

    # ── childcare ────────────────────────────────────────────────────────────
    "Trumpington Meadows Nursery":
        "https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?w=400&q=80",
    "Cherry Hinton Day Nursery":
        "https://images.unsplash.com/photo-1516627145497-ae6968895b74?w=400&q=80",
    "Acorn Childminding — Sarah T.":
        "https://images.unsplash.com/photo-1515488042361-ee00e0ddd4e4?w=400&q=80",
    "Fen Ditton Tots Childcare":
        "https://images.unsplash.com/photo-1535572290543-960a8046f5af?w=400&q=80",
    "Newnham Walnut Tree Nursery":
        "https://images.unsplash.com/photo-1526634332515-d56c5fd16991?w=400&q=80",
    "Milton Road Children's Centre":
        "https://images.unsplash.com/photo-1551966775-a4ddc8df052b?w=400&q=80",
    "Reliable Robins Babysitting Agency":
        "https://images.unsplash.com/photo-1596524430615-b46475ddff6e?w=400&q=80",
    "Chloe's Cambridge Babysitting":
        "https://images.unsplash.com/photo-1542810634-71277d95dcbb?w=400&q=80",
    "The Babysitting Co-op Cambridge":
        "https://images.unsplash.com/photo-1543248939-ff40856f65d4?w=400&q=80",
    "Cambridge Student Nannies":
        "https://images.unsplash.com/photo-1516627145497-ae6968895b74?w=400&q=80",
    "Nana Knows — Mature Babysitters":
        "https://images.unsplash.com/photo-1574169208507-84376144848b?w=400&q=80",

    # ── fitness ──────────────────────────────────────────────────────────────
    "Buggy Bootcamp Cambridge":
        "https://images.unsplash.com/photo-1434682881908-b43d0467b798?w=400&q=80",
    "ParkRun Cambridge — Family Mile":
        "https://images.unsplash.com/photo-1571008887538-b36bb32f4571?w=400&q=80",
    "Aqua Mums Cambridge":
        "https://images.unsplash.com/photo-1530549387789-4c1017266635?w=400&q=80",

    # ── homeServices ─────────────────────────────────────────────────────────
    "Cambridge Handyman Co.":
        "https://images.unsplash.com/photo-1504328345606-18bbc8c9d7d1?w=400&q=80",
    "Cambridge Plumbing Plus":
        "https://images.unsplash.com/photo-1621905251189-08b45d6a269e?w=400&q=80",
    "EcoNest Builders Cambridge":
        "https://images.unsplash.com/photo-1503387762-592deb58ef4e?w=400&q=80",
    "Bright Spark Electrical — Cambridge":
        "https://images.unsplash.com/photo-1558002038-1055907df827?w=400&q=80",
    "Tidy Gardens Cambridge":
        "https://images.unsplash.com/photo-1416879595882-3373a0480b5b?w=400&q=80",

    # ── food ─────────────────────────────────────────────────────────────────
    "Cambridge Organic Box Scheme":
        "https://images.unsplash.com/photo-1488459716781-31db52582fe9?w=400&q=80",
    "The Feeding Room Cambridge":
        "https://images.unsplash.com/photo-1555939594-58d7cb561ad1?w=400&q=80",
    "NCT Cambridge Bumps & Babies Café":
        "https://images.unsplash.com/photo-1442512595331-e89e73853f31?w=400&q=80",
    "Tiny Tummies — Baby Meal Prep":
        "https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=400&q=80",

    # ── doula ────────────────────────────────────────────────────────────────
    "Blyth Doula Services":
        "https://images.unsplash.com/photo-1584820927498-cfe5211fd8bf?w=400&q=80",
    "The Doula Tree — Cambridge":
        "https://images.unsplash.com/photo-1576765608535-5f04d1e3f289?w=400&q=80",
    "Emma Clarke — Birth Doula":
        "https://images.unsplash.com/photo-1555252333-9f8e92e65df9?w=400&q=80",
    "Sarah Webb — Postnatal Doula":
        "https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400&q=80",
    "Cambridge Natural Birth & Beyond":
        "https://images.unsplash.com/photo-1555252333-9f8e92e65df9?w=400&q=80",
    "Cambridge Birth Collective":
        "https://images.unsplash.com/photo-1546015720-b8b30df5aa27?w=400&q=80",

    # ── firstAid ─────────────────────────────────────────────────────────────
    "Little Lifesavers Cambridge":
        "https://images.unsplash.com/photo-1516574187841-cb9cc2ca948b?w=400&q=80",
    "St John Ambulance Cambridge":
        "https://images.unsplash.com/photo-1584515933487-779824d29309?w=400&q=80",
    "Cambridge First Aid Training":
        "https://images.unsplash.com/photo-1530497610245-94d3c16cda28?w=400&q=80",
    "Cambridge Red Cross — First Aid":
        "https://images.unsplash.com/photo-1607619056574-7b8d3ee536b2?w=400&q=80",
    "Tiny Hearts Education — Cambridge":
        "https://images.unsplash.com/photo-1559757148-5c350d0d3c56?w=400&q=80",

    # ── other ─────────────────────────────────────────────────────────────────
    "Cambridge Twins Club":
        "https://images.unsplash.com/photo-1476703993599-0035a21b17a9?w=400&q=80",
    "NCT Cambridge — Antenatal Courses":
        "https://images.unsplash.com/photo-1584820927498-cfe5211fd8bf?w=400&q=80",
    "Home Start Cambridge":
        "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&q=80",
    "Cambridge Bereavement Support — Baby Loss":
        "https://images.unsplash.com/photo-1518199266791-5375a83190b7?w=400&q=80",
    "Cambridge NCT — Antenatal Courses":
        "https://images.unsplash.com/photo-1584820927498-cfe5211fd8bf?w=400&q=80",
}

# ─────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT: test all URLs before writing to Firestore
# ─────────────────────────────────────────────────────────────────────────────
print("Step 1 — Pre-flight URL check...")
broken = []
for name, url in IMAGE_MAP.items():
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}, method="HEAD")
        with urllib.request.urlopen(req, timeout=6) as r:
            if r.status != 200:
                broken.append((name, url, r.status))
    except Exception as e:
        broken.append((name, url, str(e)))

if broken:
    print(f"\n❌ {len(broken)} URLs failed pre-flight:")
    for name, url, err in broken:
        print(f"   {name}: {err}")
    print("\nAborting — fix broken URLs before writing to Firestore.")
    exit(1)
else:
    print(f"  ✅ All {len(IMAGE_MAP)} URLs passed (HTTP 200)")

# ─────────────────────────────────────────────────────────────────────────────
# WRITE: update Firestore docs
# ─────────────────────────────────────────────────────────────────────────────
print("\nStep 2 — Fetching Firestore documents...")
docs = list(db.collection("local_services").stream())
print(f"  Found {len(docs)} documents")

updated = 0
skipped_empty = 0
not_in_map = []

print("\nStep 3 — Writing imageUrl fields...")
for doc in docs:
    d = doc.to_dict()
    name = d.get("name", "").strip()

    if not name:
        skipped_empty += 1
        continue

    if name not in IMAGE_MAP:
        not_in_map.append(name)
        continue

    new_url = IMAGE_MAP[name]
    doc.reference.update({"imageUrl": new_url})
    updated += 1
    print(f"  ✅ {name[:50]}")
    time.sleep(0.05)  # gentle rate-limit

print(f"\n{'─'*60}")
print(f"✅  Updated : {updated}")
print(f"⏭️  Skipped (no name) : {skipped_empty}")
if not_in_map:
    print(f"\n⚠️  {len(not_in_map)} names not found in IMAGE_MAP:")
    for n in not_in_map:
        print(f"   — {n}")
print("Done.")
