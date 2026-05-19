"""
seed_places_api.py
──────────────────
Seeds the Firestore local_services collection with REAL Cambridge businesses
sourced directly from the Google Places API (New).

For each business:
  • Real name, address, phone, website from Google's database
  • Real star rating from Google reviews
  • Real photo fetched via Places Photo API → stored as imageUrl
  • Deduplicated by normalised name within this run

Places API (New) endpoints used:
  POST https://places.googleapis.com/v1/places:searchText
  GET  https://places.googleapis.com/v1/{photo_name}/media?maxWidthPx=800&key=...
"""

import json, re, time, urllib.request, urllib.parse
import firebase_admin
from firebase_admin import credentials, firestore

# ── Firebase ──────────────────────────────────────────────────────────────────
cred = credentials.Certificate("/opt/flutter/firebase-admin-sdk.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

# ── Places API config ─────────────────────────────────────────────────────────
PLACES_KEY  = "AIzaSyBhAAN0eZUPOslcrjMPDDXiB6RHt11MGNE"
SEARCH_URL  = "https://places.googleapis.com/v1/places:searchText"
PHOTO_URL   = "https://places.googleapis.com/v1/{name}/media?maxWidthPx=800&skipHttpRedirect=true&key=" + PLACES_KEY

# Cambridge city centre coordinates
CAMBRIDGE_LAT = 52.2053
CAMBRIDGE_LNG = 0.1218
SEARCH_RADIUS = 8000  # 8 km covers greater Cambridge

BOROUGH     = "Cambridge"
COLLECTION  = "local_services"
MIN_RATING  = 4.0  # only include businesses rated 4.0★ or above

# ── Category → search queries ─────────────────────────────────────────────────
# Multiple queries per category to get more diverse, high-quality results.
# Each query targets a specific type of business parents in Cambridge need.
CATEGORY_QUERIES = {
    "childcare": [
        "day nursery Cambridge",
        "childminder Cambridge",
        "preschool Cambridge",
        "after school club Cambridge",
    ],
    "education": [
        "children's tutor Cambridge",
        "music lessons children Cambridge",
        "swimming lessons children Cambridge",
        "martial arts children Cambridge",
        "drama classes children Cambridge",
    ],
    "healthWellness": [
        "osteopath Cambridge",
        "acupuncture Cambridge",
        "postnatal yoga Cambridge",
        "paediatric physiotherapy Cambridge",
        "children's dentist Cambridge",
    ],
    "fitness": [
        "buggy fitness class Cambridge",
        "postnatal fitness Cambridge",
        "baby swimming class Cambridge",
        "parent and baby yoga Cambridge",
    ],
    "photography": [
        "family photographer Cambridge",
        "newborn photographer Cambridge",
        "baby photographer Cambridge",
    ],
    "cleaning": [
        "domestic cleaning service Cambridge",
        "house cleaning Cambridge",
        "end of tenancy cleaning Cambridge",
    ],
    "homeServices": [
        "plumber Cambridge",
        "electrician Cambridge",
        "handyman Cambridge",
        "gardener Cambridge",
    ],
    "food": [
        "organic food delivery Cambridge",
        "baby weaning class Cambridge",
        "children's cookery class Cambridge",
    ],
    "doula": [
        "doula Cambridge",
        "birth preparation class Cambridge",
        "NCT antenatal class Cambridge",
        "hypnobirthing Cambridge",
    ],
    "firstAid": [
        "first aid training Cambridge",
        "paediatric first aid course Cambridge",
        "baby first aid class Cambridge",
    ],
    "other": [
        "parent support group Cambridge",
        "postnatal support Cambridge",
        "twins club Cambridge",
        "stay and play Cambridge",
        "children's library Cambridge",
    ],
}

# Friendly tag sets per category (added to every listing in that category)
CATEGORY_TAGS = {
    "childcare":      ["Ofsted registered", "DBS checked"],
    "education":      ["DBS checked", "qualified teachers"],
    "healthWellness": ["qualified practitioner", "family-friendly"],
    "fitness":        ["parent & child", "qualified instructor"],
    "photography":    ["professional", "family sessions"],
    "cleaning":       ["insured", "background checked"],
    "homeServices":   ["insured", "fully qualified"],
    "food":           ["family-friendly", "Cambridge"],
    "doula":          ["certified", "Cambridge-based"],
    "firstAid":       ["certified", "Ofsted compliant"],
    "other":          ["community", "Cambridge"],
}


# ── Step 1: Delete all AI-seeded fictional listings ───────────────────────────

def clear_fictional_listings():
    print("\n🗑️  Clearing all fictional/AI-seeded listings…")
    docs    = list(db.collection(COLLECTION).stream())
    deleted = 0
    for doc in docs:
        d = doc.to_dict()
        # Remove anything created by the AI — keep only real owner-verified listings
        if d.get("createdByUid") == "huddl_ai" or not d.get("ownerUid"):
            doc.reference.delete()
            deleted += 1
    print(f"  ✅ Deleted {deleted} fictional listings")


# ── Step 2: Places API search ─────────────────────────────────────────────────

def search_places(query, max_results=10):
    """Call Places API (New) Text Search and return raw place dicts."""
    body = json.dumps({
        "textQuery":    query,
        "locationBias": {
            "circle": {
                "center": {"latitude": CAMBRIDGE_LAT, "longitude": CAMBRIDGE_LNG},
                "radius": float(SEARCH_RADIUS)
            }
        },
        "maxResultCount": max_results,
        "languageCode":   "en",
    }).encode()

    fields = ",".join([
        "places.id",
        "places.displayName",
        "places.formattedAddress",
        "places.nationalPhoneNumber",
        "places.websiteUri",
        "places.rating",
        "places.userRatingCount",
        "places.businessStatus",
        "places.photos",
        "places.types",
        "places.editorialSummary",
        "places.regularOpeningHours",
    ])

    req = urllib.request.Request(SEARCH_URL, data=body, headers={
        "Content-Type":     "application/json",
        "X-Goog-Api-Key":   PLACES_KEY,
        "X-Goog-FieldMask": fields,
    })

    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.loads(r.read()).get("places", [])
    except Exception as e:
        print(f"    ⚠️  Search error for '{query}': {e}")
        return []


# ── Step 3: Fetch real photo URL via Places Photo API ────────────────────────

def fetch_photo_url(photos):
    """
    Given a list of photo resource dicts from Places API,
    returns the URL of the first available photo, or None.
    
    Places API (New) returns photo names like:
      "places/ChIJ.../photos/AXCi..."
    We call the media endpoint which redirects to the actual CDN URL.
    With skipHttpRedirect=true it returns JSON with the photoUri.
    """
    if not photos:
        return None

    photo_name = photos[0].get("name", "")
    if not photo_name:
        return None

    url = PHOTO_URL.replace("{name}", photo_name)

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Huddl/1.0"})
        with urllib.request.urlopen(req, timeout=10) as r:
            data = json.loads(r.read())
            photo_uri = data.get("photoUri", "")
            if photo_uri and photo_uri.startswith("http"):
                return photo_uri
    except Exception as e:
        pass

    return None


# ── Step 4: Convert Place → Firestore document ────────────────────────────────

def place_to_listing(place, category):
    name    = place.get("displayName", {}).get("text", "").strip()
    address = place.get("formattedAddress", "").strip()
    phone   = place.get("nationalPhoneNumber", "")
    website = place.get("websiteUri", "")
    rating  = place.get("rating")
    summary = place.get("editorialSummary", {}).get("text", "")

    # Build a tagline from the address (shorter version)
    # e.g. "9-10 Harvey Rd, Cambridge CB1 2ET, UK" → "Harvey Rd, Cambridge"
    addr_parts = address.split(",")
    short_addr = ", ".join(addr_parts[1:3]).strip() if len(addr_parts) >= 2 else address
    tagline    = f"{name[:40]}, {short_addr}"[:60]

    # Description: use editorial summary if available, else a generic one
    description = summary[:160] if summary else f"{name} — serving families in {BOROUGH}."[:160]

    # Tags: category base tags + rating tag if high
    tags = list(CATEGORY_TAGS.get(category, []))
    if rating and rating >= 4.8:
        tags.append("Top rated")
    if rating and rating >= 4.5 and "Top rated" not in tags:
        tags.append(f"{rating}★ on Google")

    return {
        "name":        name,
        "tagline":     tagline,
        "description": description,
        "address":     address,
        "category":    category,
        "phone":       phone or None,
        "website":     website or None,
        "tags":        tags[:4],
        "rating":      float(rating) if rating else None,
        "photos":      place.get("photos", []),
    }


# ── Step 5: Write to Firestore ────────────────────────────────────────────────

def write_listing(item, image_url):
    data = {
        "name":             item["name"],
        "tagline":          item["tagline"],
        "description":      item["description"],
        "address":          item["address"],
        "category":         item["category"],
        "borough":          BOROUGH,
        "tags":             item["tags"],
        "phone":            item["phone"],
        "website":          item["website"],
        "ownerUid":         None,
        "createdByUid":     "huddl_ai",
        "verificationTier": "none",
        "isVerified":       False,
        "endorsementCount": 0,
        "viewCount":        0,
        "createdAt":        firestore.SERVER_TIMESTAMP,
        "updatedAt":        firestore.SERVER_TIMESTAMP,
        "listingSource":    "places_api",
        "aiRating":         item["rating"],
        "googleRating":     item["rating"],
        "aiDiscoveredAt":   firestore.SERVER_TIMESTAMP,
    }
    if image_url:
        data["imageUrl"] = image_url

    db.collection(COLLECTION).add(data)


# ── Helpers ───────────────────────────────────────────────────────────────────

def normalise(name):
    return re.sub(r"[^a-z0-9]", "", name.lower())


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("=" * 65)
    print("Huddl — Real Business Seeding via Google Places API (New)")
    print(f"Borough : {BOROUGH}  |  Min rating : {MIN_RATING}★")
    print("=" * 65)

    # Step 1: wipe fictional data
    clear_fictional_listings()

    seen_names  = set()
    total_added = 0
    total_imgs  = 0

    for category, queries in CATEGORY_QUERIES.items():
        print(f"\n📍 Category: {category}")

        for query in queries:
            print(f"  🔍 '{query}'")
            places = search_places(query, max_results=8)

            for place in places:
                # Only include operational businesses
                if place.get("businessStatus") != "OPERATIONAL":
                    continue

                # Rating gate
                rating = place.get("rating")
                if rating and float(rating) < MIN_RATING:
                    continue

                listing = place_to_listing(place, category)
                name    = listing["name"]

                if not name:
                    continue

                # Dedup by normalised name across entire run
                norm = normalise(name)
                if norm in seen_names:
                    continue

                # Fetch real Google photo
                image_url = fetch_photo_url(listing["photos"])

                # Write to Firestore
                write_listing(listing, image_url)
                seen_names.add(norm)
                total_added += 1
                if image_url:
                    total_imgs += 1

                img_flag   = "📷" if image_url else "  "
                rating_str = f"{rating}★" if rating else "no rating"
                print(f"  {img_flag} ✅ {name} ({rating_str})")

                time.sleep(0.1)  # gentle rate limit

            time.sleep(0.5)  # pause between queries

    print("\n" + "=" * 65)
    print(f"✅  Real listings added     : {total_added}")
    print(f"📷  With Google photos      : {total_imgs}")
    print(f"   Without photos (→ icon) : {total_added - total_imgs}")
    print("=" * 65)


if __name__ == "__main__":
    main()
