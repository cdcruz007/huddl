#!/usr/bin/env python3
"""
replace_icons_pass2.py — Second pass for unmapped icons not caught in pass 1.
Handles variant suffixes (_outlined, _rounded, etc.) not in the original map.
"""

import re
from pathlib import Path

# Direct mapping for all unmapped icons from pass 1 report
PASS2_MAP = {
    # Person variants
    "person_off_outlined":          "personOff",
    "person_add_outlined":          "personAdd",
    "person_remove_outlined":       "personRemove",
    "person_remove_alt_1":          "personRemove",
    # Group variants
    "group_add_outlined":           "userGroupPlus",
    "group_off_outlined":           "usersThree",
    "manage_accounts_outlined":     "manageAccounts",
    # Money / payment
    "money_off_outlined":           "moneyOff",
    # Block
    "block_outlined":               "block",
    # Publish / upload
    "publish":                      "publish",
    # Weather
    "wb_cloudy_outlined":           "cloud",
    # Fingerprint
    "fingerprint_rounded":          "fingerprint",
    # Hourglass
    "hourglass_top":                "hourglass",
    "hourglass_top_outlined":       "hourglass",
    # Save
    "save_outlined":                "save",
    "save_rounded":                 "save",
    # Thumbs outlined (not filled)
    "thumb_up_alt_outlined":        "thumbUp",
    "thumb_down_alt_outlined":      "thumbDown",
    "thumb_up_off_alt_rounded":     "thumbUp",
    "thumbs_up_down_outlined":      "thumbsUpDown",
    # Directions
    "directions_run_rounded":       "run",
    # Label
    "label_outline":                "label",
    # Filter
    "filter_list_off":              "filterOff",
    # Diversity
    "diversity_3_outlined":         "diversity",
    "diversity_1_outlined":         "diversity",
    "diversity_2_outlined":         "diversity",
    # Handshake
    "handshake_rounded":            "handshake",
    # Copy
    "copy_outlined":                "copy",
    "copy":                         "copy",
    # Contacts
    "contacts_rounded":             "contacts",
    # Mark chat
    "mark_chat_read_outlined":      "markChatRead",
    "mark_chat_unread_outlined":    "markChatUnread",
    "mark_chat_read":               "markChatRead",
    "mark_chat_unread":             "markChatUnread",
    # Night mode
    "nightlight":                   "nightMode",
    # Flight / travel
    "flight_takeoff":               "arrowUp",
    # Image
    "image_not_supported_outlined": "imageNotSupported",
    "broken_image_outlined":        "brokenImage",
    "insert_drive_file_rounded":    "file",
    # Check box
    "check_box_outlined":           "checkSquare",
    # Priority
    "priority_high_rounded":        "priority",
    # Volunteer activism
    "volunteer_activism_outlined":  "volunteerActivism",
    # Account balance
    "account_balance_outlined":     "bank",
    # Privacy tip
    "privacy_tip_outlined":         "privacy",
    "privacy_tip":                  "privacy",
    # Emergency
    "emergency_outlined":           "emergency",
    # View variants
    "view_list_outlined":           "viewList",
    "grid_view_outlined":           "gridView",
    # Upload / download outlined
    "upload_outlined":              "upload",
    "download_outlined":            "download",
    "download":                     "download",
    # Storage outlined
    "storage_outlined":             "storage",
    # Lock reset
    "lock_reset_outlined":          "lockReset",
    # Rate review / feedback
    "rate_review_outlined":         "rateReview",
    "feedback_outlined":            "feedback",
    # Add business rounded
    "add_business_rounded":         "addBusiness",
    "business_rounded":             "business",
    # Receipt
    "receipt_long_rounded":         "receipt",
    # Pause circle
    "pause_circle_outline":         "pauseCircle",
    "pause_circle_outlined":        "pauseCircle",
    # Apple logo
    "apple":                        "apple",
    # Celebration
    "celebration_outlined":         "celebration",
    "celebration_rounded":          "celebration",
    # Radio button off
    "radio_button_off":             "radioOff",
    # Facebook
    "facebook":                     "facebook",
    # Forest
    "forest":                       "tree",
    "forest_rounded":               "tree",
    # Newspaper
    "newspaper":                    "article",
    "newspaper_rounded":            "article",
    # Support (phone agent)
    "support":                      "support",
    # Music outlined
    "music_note_outlined":          "musicNote",
    # Waving hand outlined
    "waving_hand_outlined":         "waving",
    # Rounded variants of already-mapped icons
    "menu_book_rounded":            "menuBook",
    "title_rounded":                "title",
    "short_text_rounded":           "shortText",
    "image_not_supported_rounded":  "imageNotSupported",
}

SKIP_FILES = {
    "lib/theme/huddl_icons.dart",
    "lib/widgets/huddl_category_icon.dart",
    "scripts/replace_icons.py",
    "scripts/replace_icons_pass2.py",
}

def build_pattern(mapping):
    keys = sorted(mapping.keys(), key=len, reverse=True)
    escaped = "|".join(re.escape(k) for k in keys)
    return re.compile(r"\bIcons\.(" + escaped + r")\b")


def process_file(path: Path, project_root: Path, pattern, mapping, report: dict) -> bool:
    rel_path = str(path.relative_to(project_root))
    if rel_path in SKIP_FILES:
        return False

    original = path.read_text(encoding="utf-8")
    
    count = [0]
    def replace(m):
        count[0] += 1
        huddl = mapping[m.group(1)]
        report.setdefault("replaced", []).append(f"{rel_path}: Icons.{m.group(1)} → HuddlIcons.{huddl}")
        return f"HuddlIcons.{huddl}"

    text = pattern.sub(replace, original)

    if count[0] == 0:
        return False

    path.write_text(text, encoding="utf-8")
    return True


def main():
    project_root = Path("/home/user/flutter_app")
    lib_dir = project_root / "lib"
    
    pattern = build_pattern(PASS2_MAP)
    dart_files = list(lib_dir.rglob("*.dart"))

    report = {}
    changed = 0

    for f in sorted(dart_files):
        if process_file(f, project_root, pattern, PASS2_MAP, report):
            changed += 1
            print(f"  ✓ {f.relative_to(project_root)}")

    replaced = report.get("replaced", [])
    print(f"\nPass 2: {changed} files changed, {len(replaced)} additional call-sites replaced")

    # Final scan for any remaining Icons.xxx
    remaining = []
    for f in sorted(lib_dir.rglob("*.dart")):
        rel = str(f.relative_to(project_root))
        if rel in SKIP_FILES:
            continue
        text = f.read_text(encoding="utf-8")
        found = re.findall(r"\bIcons\.([a-zA-Z0-9_]+)\b", text)
        for icon in found:
            if icon not in ("fromList",):
                remaining.append(f"{rel}: Icons.{icon}")
        found_c = re.findall(r"\bCupertinoIcons\.([a-zA-Z0-9_]+)\b", text)
        for icon in found_c:
            remaining.append(f"{rel}: CupertinoIcons.{icon}")

    if remaining:
        print(f"\n⚠️  Still remaining after pass 2 ({len(remaining)}):")
        for r in remaining:
            print(f"   {r}")
    else:
        print("\n✅  Zero remaining Icons./CupertinoIcons. references!")


if __name__ == "__main__":
    main()
