// =============================================================================
// HUDDL ICON SYSTEM — single source of truth
//
// Standardises every icon on Phosphor Regular (one family, one base weight).
// Fill weight is used ONLY for active / selected / "on" states — never decoratively.
//
// ACTIVE-STATE RULE
//   isActive / isSelected / isSaved / isFavourited / isOn  →  PhosphorIconsFill.*
//   default / outline / inactive                           →  PhosphorIconsRegular.*
//
// SEMANTIC-DUPLICATE COLLAPSES (many Material variants → one Phosphor glyph)
//   Back navigation  : arrow_back / arrow_back_ios / arrow_back_ios_new /
//                      arrow_back_ios_new_rounded / arrow_back_rounded
//                      → PhosphorIconsRegular.arrowLeft
//   Forward navigation: arrow_forward / arrow_forward_ios /
//                       arrow_forward_ios_rounded / arrow_forward_rounded
//                       → PhosphorIconsRegular.arrowRight
//   Chevron left     : chevron_left / keyboard_arrow_left-equivalent
//                      → PhosphorIconsRegular.caretLeft
//   Chevron right    : chevron_right / chevron_right_rounded / keyboard_arrow_right
//                      → PhosphorIconsRegular.caretRight
//   Chevron down     : keyboard_arrow_down / keyboard_arrow_down_rounded / expand_more
//                      → PhosphorIconsRegular.caretDown
//   Chevron up       : keyboard_arrow_up / keyboard_arrow_up_rounded / expand_less
//                      → PhosphorIconsRegular.caretUp
//   Bookmarks        : bookmark / bookmark_outline / bookmark_border /
//                      bookmark_add_outlined / bookmark_added /
//                      bookmark_added_rounded / bookmark_remove_outlined
//                      → Regular = PhosphorIconsRegular.bookmark
//                        Active  = PhosphorIconsFill.bookmark
//   Clock / time     : access_time / access_time_outlined / access_time_rounded /
//                      schedule / schedule_outlined
//                      → PhosphorIconsRegular.clock
//   Star             : star / star_rounded / star_border_rounded / star_half_rounded /
//                      star_outline / star_outline_rounded
//                      → Regular = PhosphorIconsRegular.star
//                        Active  = PhosphorIconsFill.star
//   Favourite/heart  : favorite / favorite_border / favorite_border_rounded /
//                      favorite_outline
//                      → Regular = PhosphorIconsRegular.heart
//                        Active  = PhosphorIconsFill.heart
//   People/group     : people / people_outline / people_outline_rounded /
//                      people_outlined / people_rounded / people_alt_rounded /
//                      group / group_outlined / groups / groups_outlined
//                      → PhosphorIconsRegular.usersThree (group/collective)
//                        or PhosphorIconsRegular.users (pair/small group)
//   Person           : person / person_outline / person_outline_rounded /
//                      person_rounded / face / face_2 / face_3
//                      → PhosphorIconsRegular.user
//   Verified         : verified / verified_outlined / verified_rounded /
//                      verified_user / verified_user_outlined
//                      → PhosphorIconsRegular.sealCheck
//   Auto-awesome/AI  : auto_awesome / auto_awesome_outlined / auto_awesome_rounded
//                      → PhosphorIconsRegular.sparkle
//   Storefront/Shop  : storefront / storefront_outlined / storefront_rounded /
//                      store_outlined / store_mall_directory_outlined
//                      → PhosphorIconsRegular.storefront
//   Close/Clear      : close / close_outlined / close_rounded / clear / cancel /
//                      cancel_outlined
//                      → PhosphorIconsRegular.x
//   Check            : check / check_rounded / done_all
//                      → PhosphorIconsRegular.check
//   Check circle     : check_circle / check_circle_outline / check_circle_rounded
//                      → Regular = PhosphorIconsRegular.checkCircle
//                        Active  = PhosphorIconsFill.checkCircle
//   Location/Place   : location_on / location_on_outlined / location_on_rounded /
//                      place / place_outlined / place_rounded
//                      → PhosphorIconsRegular.mapPin
//   Delete/Remove    : delete / delete_outline / delete_forever /
//                      delete_forever_outlined / delete_sweep_outlined
//                      → PhosphorIconsRegular.trash
//   Edit/Pencil      : edit / edit_outlined / edit_note
//                      → PhosphorIconsRegular.pencilSimple
//   Search           : search / search_rounded / search_off / search_off_rounded
//                      → PhosphorIconsRegular.magnifyingGlass
//   Camera/Photo     : camera_alt / camera_alt_outlined / camera_alt_rounded /
//                      add_a_photo / add_a_photo_outlined
//                      → PhosphorIconsRegular.camera
//   Notifications    : notifications / notifications_active / notifications_none /
//                      notifications_off / notifications_outlined /
//                      notifications_active_outlined / notifications_off_outlined /
//                      notifications_rounded
//                      → Regular = PhosphorIconsRegular.bell
//                        Active  = PhosphorIconsFill.bell
//   Chat/Message     : chat_bubble / chat_bubble_outline / chat_bubble_outline_rounded /
//                      chat_outlined / message_outlined / comment_outlined
//                      → PhosphorIconsRegular.chatCircle
//   Share            : share / share_outlined
//                      → PhosphorIconsRegular.shareFat
//   Info             : info_outline / info_outline_rounded
//                      → PhosphorIconsRegular.info
//   Warning          : warning_amber / warning_amber_rounded / warning_rounded
//                      → PhosphorIconsRegular.warning
//   Lock             : lock / lock_outline / lock_outline_rounded / lock_outlined
//                      → PhosphorIconsRegular.lock
//   Trending         : trending_up / trending_down
//                      → PhosphorIconsRegular.trendUp / trendDown
//   Refresh/Update   : refresh / refresh_rounded / update / restore / repeat /
//                      replay_outlined
//                      → PhosphorIconsRegular.arrowClockwise
//   Photo library    : photo_library / photo_library_outlined / photo_library_rounded /
//                      image / image_outlined / add_photo_alternate_outlined
//                      → PhosphorIconsRegular.images
//   Poll/Bar chart   : poll_outlined / poll_rounded / bar_chart_outlined /
//                      bar_chart_rounded / insights
//                      → PhosphorIconsRegular.chartBar
//   Event/Calendar   : event / event_outlined / event_rounded / calendar_today /
//                      calendar_today_outlined / calendar_month_outlined /
//                      event_available / event_available_outlined /
//                      event_busy / event_busy_outlined /
//                      event_note / event_note_outlined
//                      → PhosphorIconsRegular.calendar
//   Tune/Filter      : tune / tune_rounded
//                      → PhosphorIconsRegular.slidersHorizontal
//   Sort             : sort_by_alpha / sort_by_alpha_outlined
//                      → PhosphorIconsRegular.sortAscending
//   Phone            : phone / phone_outlined / phone_in_talk_outlined
//                      → PhosphorIconsRegular.phone
//   Mic              : mic / mic_none / mic_outlined / mic_off_outlined
//                      → Regular = PhosphorIconsRegular.microphone
//                        Muted   = PhosphorIconsRegular.microphoneSlash
//   More horizontal  : more_horiz / more_horiz_rounded
//                      → PhosphorIconsRegular.dotsThree
//   More vertical    : more_vert
//                      → PhosphorIconsRegular.dotsThreeVertical
//   Report/Flag      : flag / flag_outlined
//                      → PhosphorIconsRegular.flag
//   Shield/Security  : shield / shield_outlined / security / security_rounded
//                      → PhosphorIconsRegular.shield
//   Topic/Category   : topic / topic_outlined / topic_rounded / category
//                      → PhosphorIconsRegular.tag
//   School/Education : school / school_outlined
//                      → PhosphorIconsRegular.graduationCap
//   Medical/Health   : local_hospital / local_hospital_outlined /
//                      medical_services_outlined / health_and_safety_outlined
//                      → PhosphorIconsRegular.firstAidKit
//   Sports general   : sports / sports_outlined → PhosphorIconsRegular.trophy
//   Restaurant/Food  : restaurant / restaurant_outlined / lunch_dining /
//                      outdoor_grill / no_food / coffee / coffee_outlined /
//                      free_breakfast → context-specific, see map below
//   Work/Brief       : work / work_outline / work_outline_rounded
//                      → PhosphorIconsRegular.briefcase
//   Mic             : record_voice_over_outlined → PhosphorIconsRegular.microphone
//   Send             : send / send_outlined / send_rounded → PhosphorIconsRegular.paperPlaneRight
//   Reply            : reply / reply_rounded / forward / forward_outlined
//                      → PhosphorIconsRegular.arrowBendUpLeft
//
// NO-EQUIVALENT LIST (requires human review — left as PhosphorIconsRegular.question):
//   Icons.g_mobiledata       — mobile data speed indicator; no Phosphor equivalent
//   Icons.entries            — undefined Material symbol; no Phosphor equivalent
//   Icons.fiber_new          — "NEW" badge text; use text label instead
//   Icons.face_retouching_natural_rounded — beauty filter; no direct equivalent
//   Icons.sign_language      — uses Phosphor.handWaving as closest approximation
//   Icons.pregnant_woman / Icons.pregnant_woman_outlined — uses Phosphor.baby
//   Icons.family_restroom    — uses Phosphor.usersThree (closest)
//   Icons.baby_changing_station — uses Phosphor.baby
//   Icons.north_west / Icons.north_outlined / Icons.south_outlined — directional arrows
//   Icons.subdirectory_arrow_right / Icons.subdirectory_arrow_right_rounded
//                            → PhosphorIconsRegular.arrowElbowDownRight
//   Icons.pending_actions    — uses Phosphor.clockCountdown
//   Icons.upcoming_outlined  — uses Phosphor.calendarCheck
//   Icons.shortcut_rounded   — uses Phosphor.arrowBendRightDown
// =============================================================================

import 'package:phosphor_flutter/phosphor_flutter.dart';

// Re-export so every file only needs to import huddl_icons.dart
export 'package:phosphor_flutter/phosphor_flutter.dart'
    show
        PhosphorIconsRegular,
        PhosphorIconsFill,
        PhosphorIconsBold,
        PhosphorIcon;

/// Huddl icon constants — use these names throughout the app.
/// Each constant is the Phosphor Regular glyph for that semantic meaning.
/// For active/selected states, use the Fill variant: `HuddlIcons.bookmarkFill`.
abstract final class HuddlIcons {
  // ── Navigation ─────────────────────────────────────────────────────────────
  /// Back navigation (replaces all 5 arrow_back variants)
  static const arrowBack = PhosphorIconsRegular.arrowLeft;

  /// Forward navigation (replaces all 4 arrow_forward variants)
  static const arrowForward = PhosphorIconsRegular.arrowRight;

  /// Upward (scroll to top, sort ascending indicator)
  static const arrowUp = PhosphorIconsRegular.arrowUp;

  /// Downward
  static const arrowDown = PhosphorIconsRegular.arrowDown;

  /// Chevron / caret left (replaces chevron_left)
  static const caretLeft = PhosphorIconsRegular.caretLeft;

  /// Chevron / caret right (replaces chevron_right, chevron_right_rounded)
  static const caretRight = PhosphorIconsRegular.caretRight;

  /// Chevron / caret down (replaces keyboard_arrow_down, expand_more)
  static const caretDown = PhosphorIconsRegular.caretDown;

  /// Chevron / caret up (replaces keyboard_arrow_up, expand_less)
  static const caretUp = PhosphorIconsRegular.caretUp;

  // ── People / Social ────────────────────────────────────────────────────────
  /// Single person / profile (replaces person, person_outline, face variants)
  static const user = PhosphorIconsRegular.user;
  static const userFill = PhosphorIconsFill.user;

  /// Add person
  static const userPlus = PhosphorIconsRegular.userPlus;

  /// Remove person
  static const userMinus = PhosphorIconsRegular.userMinus;

  /// Person off / blocked
  static const userX = PhosphorIconsRegular.userCircleMinus;

  /// Person search
  static const userSearch = PhosphorIconsRegular.userFocus;

  /// Two people / pair
  static const users = PhosphorIconsRegular.users;

  /// Group / many people (replaces people, group, groups variants)
  static const usersThree = PhosphorIconsRegular.usersThree;
  static const usersThreeFill = PhosphorIconsFill.usersThree;

  /// Add to group
  static const userGroupPlus = PhosphorIconsRegular.userCirclePlus;

  /// Leave / remove from group
  static const userGroupMinus = PhosphorIconsRegular.userCircleMinus;

  // ── Content Actions ────────────────────────────────────────────────────────
  /// Bookmark / save item (outline = default)
  static const bookmark = PhosphorIconsRegular.bookmark;

  /// Bookmark active/saved (fill = active state)
  static const bookmarkFill = PhosphorIconsFill.bookmark;

  /// Add bookmark
  static const bookmarkPlus = PhosphorIconsRegular.bookmarks;

  /// Heart / favourite (outline = default)
  static const heart = PhosphorIconsRegular.heart;

  /// Heart active/liked (fill = active state)
  static const heartFill = PhosphorIconsFill.heart;

  /// Star (outline = default)
  static const star = PhosphorIconsRegular.star;

  /// Star active/rated (fill = active state)
  static const starFill = PhosphorIconsFill.star;

  /// Star half
  static const starHalf = PhosphorIconsRegular.starHalf;

  /// Thumbs up (outline = default)
  static const thumbUp = PhosphorIconsRegular.thumbsUp;
  static const thumbUpFill = PhosphorIconsFill.thumbsUp;

  /// Thumbs down (outline = default)
  static const thumbDown = PhosphorIconsRegular.thumbsDown;
  static const thumbDownFill = PhosphorIconsFill.thumbsDown;

  /// Both thumbs (undecided / vote)
  static const thumbsUpDown = PhosphorIconsRegular.handshake;

  // ── Communication ──────────────────────────────────────────────────────────
  /// Chat / message bubble (replaces all chat variants)
  static const chat = PhosphorIconsRegular.chatCircle;
  static const chatFill = PhosphorIconsFill.chatCircle;

  /// Chat with dots (active / typing)
  static const chatDots = PhosphorIconsRegular.chatCircleDots;

  /// Forum / multi-bubble discussion
  static const forum = PhosphorIconsRegular.chats;

  /// Send message (replaces send, send_outlined, send_rounded)
  static const send = PhosphorIconsRegular.paperPlaneRight;
  static const sendFill = PhosphorIconsFill.paperPlaneRight;

  /// Reply (replaces reply, reply_rounded)
  static const reply = PhosphorIconsRegular.arrowBendUpLeft;

  /// Forward message (replaces forward, forward_outlined)
  static const forward = PhosphorIconsRegular.arrowBendUpRight;

  /// Share (replaces share, share_outlined)
  static const share = PhosphorIconsRegular.shareFat;

  /// Copy
  static const copy = PhosphorIconsRegular.copy;

  /// Phone (replaces phone, phone_outlined, phone_in_talk_outlined)
  static const phone = PhosphorIconsRegular.phone;

  /// Email / mail (replaces email_outlined, mail_outline, mark_email_unread_outlined)
  static const email = PhosphorIconsRegular.envelope;
  static const emailFill = PhosphorIconsFill.envelope;

  /// Mark read
  static const markRead = PhosphorIconsRegular.checkCircle;

  /// Mark unread
  static const markUnread = PhosphorIconsRegular.circleHalf;

  // ── Notifications ──────────────────────────────────────────────────────────
  /// Bell / notification (replaces all notification variants)
  static const bell = PhosphorIconsRegular.bell;
  static const bellFill = PhosphorIconsFill.bell;

  /// Bell ringing / active notification
  static const bellRinging = PhosphorIconsRegular.bellRinging;
  static const bellRingingFill = PhosphorIconsFill.bellRinging;

  /// Bell slash / muted
  static const bellSlash = PhosphorIconsRegular.bellSlash;

  // ── Time / Calendar ────────────────────────────────────────────────────────
  /// Clock (replaces access_time / schedule and all their variants)
  static const clock = PhosphorIconsRegular.clock;
  static const clockFill = PhosphorIconsFill.clock;

  /// Timer / alarm
  static const alarm = PhosphorIconsRegular.alarm;

  /// Countdown / pending
  static const clockCountdown = PhosphorIconsRegular.clockCountdown;

  /// Calendar (replaces all event / calendar variants)
  static const calendar = PhosphorIconsRegular.calendar;
  static const calendarFill = PhosphorIconsFill.calendar;

  /// Calendar with check
  static const calendarCheck = PhosphorIconsRegular.calendarCheck;

  /// Calendar + (add event)
  static const calendarPlus = PhosphorIconsRegular.calendarPlus;

  /// Calendar X (busy / declined)
  static const calendarX = PhosphorIconsRegular.calendarX;

  // ── Search & Navigation ────────────────────────────────────────────────────
  /// Search (replaces search, search_rounded, search_off, search_off_rounded)
  static const search = PhosphorIconsRegular.magnifyingGlass;

  /// Search off / clear search
  static const searchOff = PhosphorIconsRegular.magnifyingGlassMinus;

  /// Home
  static const home = PhosphorIconsRegular.house;
  static const homeFill = PhosphorIconsFill.house;

  /// Map / location map
  static const map = PhosphorIconsRegular.mapTrifold;

  /// Location pin (replaces location_on / place and all their variants)
  static const locationPin = PhosphorIconsRegular.mapPin;
  static const locationPinFill = PhosphorIconsFill.mapPin;

  /// Location off
  static const locationOff = PhosphorIconsRegular.mapPin; // mapPinSlash not in 2.0.1; use plain pin

  /// Explore / compass
  static const explore = PhosphorIconsRegular.compass;

  /// Directions (walk)
  static const walk = PhosphorIconsRegular.personSimpleWalk;

  /// Directions (run)
  static const run = PhosphorIconsRegular.personSimpleRun;

  /// Near me
  static const nearMe = PhosphorIconsRegular.navigationArrow;

  // ── Edit & Content ─────────────────────────────────────────────────────────
  /// Edit / pencil (replaces edit, edit_outlined, edit_note)
  static const edit = PhosphorIconsRegular.pencilSimple;

  /// Edit location
  static const editLocation = PhosphorIconsRegular.mapPin;

  /// Title / heading
  static const title = PhosphorIconsRegular.textT;

  /// Description / document text
  static const description = PhosphorIconsRegular.fileText;

  /// Assignment / clipboard task
  static const assignment = PhosphorIconsRegular.clipboardText;

  /// Article / news
  static const article = PhosphorIconsRegular.article;

  /// Short text
  static const shortText = PhosphorIconsRegular.textAlignLeft;

  /// Menu book / reading
  static const menuBook = PhosphorIconsRegular.bookOpen;

  /// Note / edit note
  static const note = PhosphorIconsRegular.notePencil;

  // ── Media & Files ──────────────────────────────────────────────────────────
  /// Camera (replaces camera_alt, add_a_photo and all variants)
  static const camera = PhosphorIconsRegular.camera;

  /// Camera add
  static const cameraPlus = PhosphorIconsRegular.cameraPlus;

  /// Photo / image (replaces image, image_outlined)
  static const image = PhosphorIconsRegular.image;

  /// Photo library / gallery (replaces photo_library and all variants)
  static const photoLibrary = PhosphorIconsRegular.images;
  static const photoLibraryFill = PhosphorIconsFill.images;

  /// Video camera
  static const videocam = PhosphorIconsRegular.videoCamera;

  /// Microphone (replaces mic, mic_none, mic_outlined)
  static const mic = PhosphorIconsRegular.microphone;
  static const micFill = PhosphorIconsFill.microphone;

  /// Microphone muted (replaces mic_off_outlined)
  static const micOff = PhosphorIconsRegular.microphoneSlash;

  /// Voice / record voice over
  static const voiceOver = PhosphorIconsRegular.microphone;

  /// File / document
  static const file = PhosphorIconsRegular.file;

  /// Insert file
  static const fileInsert = PhosphorIconsRegular.fileArrowUp;

  /// Download
  static const download = PhosphorIconsRegular.downloadSimple;

  /// Upload
  static const upload = PhosphorIconsRegular.uploadSimple;

  /// Cloud
  static const cloud = PhosphorIconsRegular.cloud;

  /// Cloud done / synced
  static const cloudDone = PhosphorIconsRegular.cloudCheck;

  /// Cloud off
  static const cloudOff = PhosphorIconsRegular.cloudSlash;

  /// Backup (cloud upload)
  static const backup = PhosphorIconsRegular.cloudArrowUp;

  /// Storage
  static const storage = PhosphorIconsRegular.database;

  /// Play audio/video
  static const play = PhosphorIconsRegular.play;
  static const playFill = PhosphorIconsFill.play;

  /// Play circle
  static const playCircle = PhosphorIconsRegular.playCircle;

  /// Pause
  static const pause = PhosphorIconsRegular.pause;

  /// Pause circle
  static const pauseCircle = PhosphorIconsRegular.pauseCircle;

  /// Stop
  static const stop = PhosphorIconsRegular.stop;

  /// Stop circle
  static const stopCircle = PhosphorIconsRegular.stopCircle;

  /// Record
  static const record = PhosphorIconsRegular.record;

  /// Music note
  static const musicNote = PhosphorIconsRegular.musicNote;

  // ── Commerce & Business ────────────────────────────────────────────────────
  /// Storefront / shop (replaces storefront and all variants)
  static const storefront = PhosphorIconsRegular.storefront;
  static const storefrontFill = PhosphorIconsFill.storefront;

  /// Shopping bag
  static const shoppingBag = PhosphorIconsRegular.shoppingBag;

  /// Price tag / sell
  static const sellTag = PhosphorIconsRegular.tag;
  static const sellTagFill = PhosphorIconsFill.tag;

  /// Local offer / discount
  static const localOffer = PhosphorIconsRegular.tagSimple;

  /// Credit card / payment
  static const creditCard = PhosphorIconsRegular.creditCard;

  /// Payment / money
  static const payment = PhosphorIconsRegular.money;

  /// Attach money
  static const money = PhosphorIconsRegular.currencyDollar;

  /// Money off / free
  static const moneyOff = PhosphorIconsRegular.prohibit;

  /// Receipt
  static const receipt = PhosphorIconsRegular.receipt;

  /// Bank / account balance
  static const bank = PhosphorIconsRegular.bank;

  /// Business / office
  static const business = PhosphorIconsRegular.buildings;

  /// Work / briefcase (replaces work, work_outline, work_outline_rounded)
  static const work = PhosphorIconsRegular.briefcase;
  static const workFill = PhosphorIconsFill.briefcase;

  // ── Safety, Security & Privacy ─────────────────────────────────────────────
  /// Lock (replaces lock, lock_outline and variants)
  static const lock = PhosphorIconsRegular.lock;
  static const lockFill = PhosphorIconsFill.lock;

  /// Lock open
  static const lockOpen = PhosphorIconsRegular.lockOpen;

  /// Lock reset
  static const lockReset = PhosphorIconsRegular.lockKeyOpen;

  /// Shield (replaces shield, shield_outlined, security, security_rounded)
  static const shield = PhosphorIconsRegular.shield;
  static const shieldFill = PhosphorIconsFill.shield;

  /// Shield check / verified user (replaces verified_user, verified_user_outlined)
  static const shieldCheck = PhosphorIconsRegular.shieldCheck;
  static const shieldCheckFill = PhosphorIconsFill.shieldCheck;

  /// Privacy / eye with shield
  static const privacy = PhosphorIconsRegular.shieldCheck;

  /// Fingerprint (biometric)
  static const fingerprint = PhosphorIconsRegular.fingerprint;

  /// Key
  static const key = PhosphorIconsRegular.key;

  /// Block / ban
  static const block = PhosphorIconsRegular.prohibit;

  /// Block (user) / person off
  static const personOff = PhosphorIconsRegular.userMinus;

  // ── Status & Feedback ──────────────────────────────────────────────────────
  /// Info (replaces info_outline, info_outline_rounded)
  static const info = PhosphorIconsRegular.info;
  static const infoFill = PhosphorIconsFill.info;

  /// Warning (replaces warning_amber, warning_amber_rounded, warning_rounded)
  static const warning = PhosphorIconsRegular.warning;
  static const warningFill = PhosphorIconsFill.warning;

  /// Error / danger
  static const error = PhosphorIconsRegular.warningCircle;
  static const errorFill = PhosphorIconsFill.warningCircle;

  /// Emergency
  static const emergency = PhosphorIconsRegular.warningOctagon;

  /// Check (replaces check, check_rounded, done_all)
  static const check = PhosphorIconsRegular.check;

  /// Check circle (replaces check_circle / check_circle_outline variants)
  static const checkCircle = PhosphorIconsRegular.checkCircle;
  static const checkCircleFill = PhosphorIconsFill.checkCircle;

  /// Check square
  static const checkSquare = PhosphorIconsRegular.checkSquare;
  static const checkSquareFill = PhosphorIconsFill.checkSquare;

  /// Checklist
  static const checklist = PhosphorIconsRegular.listChecks;

  /// Check box
  static const checkBox = PhosphorIconsRegular.checkSquare;
  static const checkBoxFill = PhosphorIconsFill.checkSquare;

  /// Radio button unchecked
  static const radioOff = PhosphorIconsRegular.circle;

  /// Radio button checked
  static const radioOn = PhosphorIconsRegular.checkCircle;
  static const radioOnFill = PhosphorIconsFill.checkCircle;

  /// Circle (generic dot / status)
  static const circle = PhosphorIconsRegular.circle;
  static const circleFill = PhosphorIconsFill.circle;

  /// Remove circle
  static const removeCircle = PhosphorIconsRegular.minusCircle;

  /// Cancel / dismiss
  static const cancel = PhosphorIconsRegular.xCircle;

  /// Priority / exclamation
  static const priority = PhosphorIconsRegular.warning;

  // ── UI Controls ────────────────────────────────────────────────────────────
  /// Close / X (replaces close, close_outlined, close_rounded, clear, cancel, cancel_outlined)
  static const close = PhosphorIconsRegular.x;

  /// Add / plus (replaces add, add_rounded)
  static const add = PhosphorIconsRegular.plus;

  /// Add circle
  static const addCircle = PhosphorIconsRegular.plusCircle;
  static const addCircleFill = PhosphorIconsFill.plusCircle;

  /// Add business / store
  static const addBusiness = PhosphorIconsRegular.storefront;

  /// Remove / minus
  static const remove = PhosphorIconsRegular.minus;

  /// More horizontal (replaces more_horiz, more_horiz_rounded)
  static const moreHoriz = PhosphorIconsRegular.dotsThree;

  /// More vertical (replaces more_vert)
  static const moreVert = PhosphorIconsRegular.dotsThreeVertical;

  /// Menu / hamburger
  static const menu = PhosphorIconsRegular.list;

  /// Grid view
  static const gridView = PhosphorIconsRegular.gridFour;

  /// List view
  static const listView = PhosphorIconsRegular.listBullets;

  /// Filter / tune (replaces tune, tune_rounded)
  static const filter = PhosphorIconsRegular.slidersHorizontal;
  static const filterFill = PhosphorIconsFill.slidersHorizontal;

  /// Filter off
  static const filterOff = PhosphorIconsRegular.funnel;

  /// Sort ascending (replaces sort_by_alpha)
  static const sortAscending = PhosphorIconsRegular.sortAscending;

  /// Sort descending
  static const sortDescending = PhosphorIconsRegular.sortDescending;

  /// View list
  static const viewList = PhosphorIconsRegular.listBullets;

  /// Open in new / external link (replaces open_in_new, open_in_new_rounded)
  static const openInNew = PhosphorIconsRegular.arrowSquareOut;

  /// Open in browser
  static const openInBrowser = PhosphorIconsRegular.globeSimple;

  /// Link (replaces link, link_rounded)
  static const link = PhosphorIconsRegular.link;

  /// Pin (replaces push_pin, push_pin_outlined)
  static const pin = PhosphorIconsRegular.pushPin;
  static const pinFill = PhosphorIconsFill.pushPin;

  /// Delete / trash (replaces delete, delete_outline, delete_forever, delete_sweep)
  static const delete = PhosphorIconsRegular.trash;
  static const deleteFill = PhosphorIconsFill.trash;

  /// Archive
  static const archive = PhosphorIconsRegular.archive;

  /// Save (cloud save)
  static const save = PhosphorIconsRegular.cloudArrowUp;

  /// Refresh / reload (replaces refresh, refresh_rounded, update, restore, repeat)
  static const refresh = PhosphorIconsRegular.arrowClockwise;

  /// Redo / repeat once
  static const redo = PhosphorIconsRegular.arrowCounterClockwise;

  /// Publish / upload
  static const publish = PhosphorIconsRegular.uploadSimple;

  /// Settings / gear (replaces settings_outlined)
  static const settings = PhosphorIconsRegular.gear;
  static const settingsFill = PhosphorIconsFill.gear;

  /// Language / globe (replaces language, language_outlined, public)
  static const language = PhosphorIconsRegular.globe;

  /// Laptop / device
  static const laptop = PhosphorIconsRegular.laptop;

  /// Phone (device, replaces phone_android, phone_iphone)
  static const phoneDevice = PhosphorIconsRegular.deviceMobile;

  // ── Visibility ─────────────────────────────────────────────────────────────
  /// Show / visibility (replaces visibility_outlined)
  static const visibility = PhosphorIconsRegular.eye;
  static const visibilityFill = PhosphorIconsFill.eye;

  /// Hide / visibility off (replaces visibility_off_outlined)
  static const visibilityOff = PhosphorIconsRegular.eyeSlash;

  // ── Categories & Content Types ─────────────────────────────────────────────
  /// Topic / tag (replaces topic, topic_outlined, topic_rounded, category)
  static const topic = PhosphorIconsRegular.tag;

  /// Label / tag
  static const label = PhosphorIconsRegular.tag;

  /// Flag / report (replaces flag, flag_outlined)
  static const flag = PhosphorIconsRegular.flag;
  static const flagFill = PhosphorIconsFill.flag;

  /// Sentiment dissatisfied
  static const sentimentBad = PhosphorIconsRegular.smileySad;

  /// Emoji / reaction (replaces emoji_emotions)
  static const emoji = PhosphorIconsRegular.smiley;

  /// Emoji events / celebration (replaces emoji_events)
  static const emojiEvents = PhosphorIconsRegular.trophy;

  // ── Community & Social ─────────────────────────────────────────────────────
  /// Waving hand (greeting)
  static const waving = PhosphorIconsRegular.handWaving;

  /// Handshake / collaboration
  static const handshake = PhosphorIconsRegular.handshake;

  /// Volunteer / helping hand
  static const volunteer = PhosphorIconsRegular.handHeart;

  /// Diversity / inclusion
  static const diversity = PhosphorIconsRegular.usersThree;

  /// Campaign / megaphone (replaces campaign_outlined)
  static const campaign = PhosphorIconsRegular.megaphone;

  /// Poll / survey (replaces poll_outlined, poll_rounded)
  static const poll = PhosphorIconsRegular.chartBar;
  static const pollFill = PhosphorIconsFill.chartBar;

  /// Bar chart / insights (replaces bar_chart_outlined, bar_chart_rounded, insights)
  static const barChart = PhosphorIconsRegular.chartBar;
  static const barChartFill = PhosphorIconsFill.chartBar;

  /// How to vote / ballot
  static const vote = PhosphorIconsRegular.checkSquare;

  // ── Health & Wellness ──────────────────────────────────────────────────────
  /// Medical / first aid (replaces local_hospital, medical_services, health_and_safety)
  static const medical = PhosphorIconsRegular.firstAidKit;

  /// Psychology / mental health (replaces psychology_rounded, psychology_alt_outlined)
  static const psychology = PhosphorIconsRegular.brain;

  /// Self improvement / wellness (replaces self_improvement)
  static const wellness = PhosphorIconsRegular.sparkle;

  /// Spa / relaxation
  static const spa = PhosphorIconsRegular.flower;

  /// Fitness / gym (replaces fitness_center)
  static const fitness = PhosphorIconsRegular.barbell;

  /// Wheelchair / accessibility (replaces accessibility_new, accessibility_new_rounded)
  static const accessibility = PhosphorIconsRegular.wheelchair;

  // ── Food & Lifestyle ───────────────────────────────────────────────────────
  /// Restaurant / fork & knife (replaces restaurant, restaurant_outlined)
  static const restaurant = PhosphorIconsRegular.forkKnife;

  /// Coffee (replaces coffee, coffee_outlined, free_breakfast)
  static const coffee = PhosphorIconsRegular.coffee;

  /// Lunch / food (replaces lunch_dining)
  static const food = PhosphorIconsRegular.forkKnife;

  /// Outdoor grill / BBQ (replaces outdoor_grill)
  static const grill = PhosphorIconsRegular.campfire;

  /// Park / outdoor (replaces park, park_outlined)
  static const park = PhosphorIconsRegular.park;

  /// Eco / nature (replaces eco)
  static const eco = PhosphorIconsRegular.leaf;

  /// Forest / tree
  static const tree = PhosphorIconsRegular.tree;

  /// Pool / swimming (replaces pool)
  static const pool = PhosphorIconsRegular.swimmingPool;

  // ── Sports & Activities ────────────────────────────────────────────────────
  /// Sports generic (replaces sports, sports_outlined)
  static const sports = PhosphorIconsRegular.trophy;

  /// Soccer (replaces sports_soccer)
  static const soccer = PhosphorIconsRegular.soccerBall;

  /// Tennis (replaces sports_tennis)
  static const tennis = PhosphorIconsRegular.tennisBall;

  /// Golf (replaces sports_golf)
  static const golf = PhosphorIconsRegular.trophy; // golfBall not in 2.0.1

  /// Gymnastics (replaces sports_gymnastics)
  static const gymnastics = PhosphorIconsRegular.personSimpleRun;

  // ── Family & Children ──────────────────────────────────────────────────────
  /// Baby / infant (replaces baby_changing_station)
  static const baby = PhosphorIconsRegular.baby;

  /// Child care (replaces child_care, child_care_outlined)
  static const childCare = PhosphorIconsRegular.baby;

  /// Child friendly / pram (replaces child_friendly)
  static const childFriendly = PhosphorIconsRegular.baby;

  /// Pregnant (replaces pregnant_woman, pregnant_woman_outlined)
  /// → closest approximation; flag for review
  static const pregnant = PhosphorIconsRegular.baby;

  /// Family restroom / family (replaces family_restroom)
  static const family = PhosphorIconsRegular.usersThree;

  /// Backpack / school bag (replaces backpack)
  static const backpack = PhosphorIconsRegular.backpack;

  /// Toys (replaces toys)
  static const toys = PhosphorIconsRegular.pinwheel;

  /// Chair / furniture
  static const chair = PhosphorIconsRegular.armchair;

  /// Checkroom / wardrobe
  static const wardrobe = PhosphorIconsRegular.coatHanger;

  // ── Education ─────────────────────────────────────────────────────────────
  /// School / graduation (replaces school, school_outlined)
  static const school = PhosphorIconsRegular.graduationCap;

  /// Auto stories / books
  static const books = PhosphorIconsRegular.books;

  // ── AI & Tech ──────────────────────────────────────────────────────────────
  /// AI / auto awesome / sparkle (replaces auto_awesome and all variants)
  static const ai = PhosphorIconsRegular.sparkle;
  static const aiFill = PhosphorIconsFill.sparkle;

  /// Robot / smart toy (replaces smart_toy_outlined)
  static const robot = PhosphorIconsRegular.robot;

  /// Brain / intelligence
  static const brain = PhosphorIconsRegular.brain;

  /// Wifi (replaces wifi, wifi_outlined, wifi_rounded)
  static const wifi = PhosphorIconsRegular.wifiHigh;

  /// Wifi off (replaces wifi_off_rounded)
  static const wifiOff = PhosphorIconsRegular.wifiSlash;

  // ── Achievements & Status ──────────────────────────────────────────────────
  /// Verified / seal check (replaces verified, verified_outlined, verified_rounded)
  static const verified = PhosphorIconsRegular.sealCheck;
  static const verifiedFill = PhosphorIconsFill.sealCheck;

  /// Verified user (replaces verified_user, verified_user_outlined)
  static const verifiedUser = PhosphorIconsRegular.shieldCheck;
  static const verifiedUserFill = PhosphorIconsFill.shieldCheck;

  /// Premium / workspace premium
  static const premium = PhosphorIconsRegular.crown;
  static const premiumFill = PhosphorIconsFill.crown;

  /// Medal / award
  static const medal = PhosphorIconsRegular.medal;

  /// Rate review
  static const rateReview = PhosphorIconsRegular.star;

  /// Trending up
  static const trendingUp = PhosphorIconsRegular.trendUp;

  /// Trending down
  static const trendingDown = PhosphorIconsRegular.trendDown;

  /// History / hourglass
  static const history = PhosphorIconsRegular.clockCounterClockwise;

  /// Hourglass
  static const hourglass = PhosphorIconsRegular.hourglass;

  // ── Subscriptions & Payments ──────────────────────────────────────────────
  /// Subscription / renew
  static const subscription = PhosphorIconsRegular.arrowClockwise;

  /// Confirmation number / ticket
  static const ticket = PhosphorIconsRegular.ticket;

  /// Pending / loading
  static const pending = PhosphorIconsRegular.clockCountdown;

  // ── Directions & Movement ─────────────────────────────────────────────────
  /// Subdirectory arrow right (replaces subdirectory_arrow_right variants)
  static const subArrowRight = PhosphorIconsRegular.arrowElbowDownRight;

  /// Shortcut
  static const shortcut = PhosphorIconsRegular.arrowBendRightDown;

  // ── NO-EQUIVALENT FALLBACKS (flagged for review) ──────────────────────────
  /// g_mobiledata — no Phosphor equivalent; using generic signal icon
  static const gMobiledata = PhosphorIconsRegular.cellSignalFull;

  /// entries — undefined; using list icon
  static const entries = PhosphorIconsRegular.listBullets;

  /// fiber_new — "NEW" badge; use text label; using sparkle as visual proxy
  static const fiberNew = PhosphorIconsRegular.sparkle;

  /// face_retouching_natural_rounded — no equivalent; using magic wand
  static const faceRetouching = PhosphorIconsRegular.magicWand;

  /// sign_language — using hand waving as approximation
  static const signLanguage = PhosphorIconsRegular.handWaving;

  /// apple — brand logo; using device mobile as approximation
  static const apple = PhosphorIconsRegular.appleLogo;

  /// facebook — brand logo
  static const facebook = PhosphorIconsRegular.facebookLogo;

  /// theater_comedy — using masks
  static const theater = PhosphorIconsRegular.maskHappy;

  /// celebration / party — using confetti
  static const celebration = PhosphorIconsRegular.confetti;

  /// man — using person
  static const man = PhosphorIconsRegular.user;

  // ── Admin / Moderation ────────────────────────────────────────────────────
  /// Admin panel / settings panel
  static const adminPanel = PhosphorIconsRegular.shieldCheck;

  /// Manage accounts
  static const manageAccounts = PhosphorIconsRegular.userGear;

  /// Support agent (replaces support_agent_outlined, support)
  static const support = PhosphorIconsRegular.headset;

  /// Summarize / report (replaces summarize_outlined)
  static const summarize = PhosphorIconsRegular.clipboardText;

  /// Feedback
  static const feedback = PhosphorIconsRegular.chatCircleDots;

  /// Question answer (replaces question_answer_outlined)
  static const questionAnswer = PhosphorIconsRegular.chatTeardropDots;

  /// How to vote
  static const howToVote = PhosphorIconsRegular.checkSquare;

  /// Legal / gavel (replaces gavel_outlined, gavel_rounded)
  static const gavel = PhosphorIconsRegular.gavel;

  /// Balance (replaces balance_outlined)
  static const balance = PhosphorIconsRegular.scales;

  /// Extension / puzzle
  static const extension = PhosphorIconsRegular.puzzlePiece;

  // ── Misc / Specific ───────────────────────────────────────────────────────
  /// Night mode / bedtime
  static const nightMode = PhosphorIconsRegular.moon;

  /// Flash on / lightning
  static const flash = PhosphorIconsRegular.lightning;

  /// All inclusive / infinite
  static const allInclusive = PhosphorIconsRegular.infinity;

  /// Layers (replaces layers_outlined)
  static const layers = PhosphorIconsRegular.stack;

  /// Summarize / palette (replaces palette_outlined)
  static const palette = PhosphorIconsRegular.palette;

  /// Brush / paint
  static const brush = PhosphorIconsRegular.paintBrush;

  /// Rocket launch
  static const rocket = PhosphorIconsRegular.rocket;

  /// Lightbulb / tip (replaces lightbulb, lightbulb_outline)
  static const lightbulb = PhosphorIconsRegular.lightbulb;
  static const lightbulbFill = PhosphorIconsFill.lightbulb;

  /// Inbox
  static const inbox = PhosphorIconsRegular.tray;

  /// Upcoming (replaces upcoming_outlined)
  static const upcoming = PhosphorIconsRegular.calendarCheck;

  /// Broken image (placeholder for failed images)
  static const brokenImage = PhosphorIconsRegular.image; // imageBroken not in 2.0.1

  /// Image not supported
  static const imageNotSupported = PhosphorIconsRegular.prohibit;

  /// Cloud off (offline)
  static const offline = PhosphorIconsRegular.cloudSlash;

  // ── Direction chips (N/S used in compass UI) ──────────────────────────────
  static const northWest = PhosphorIconsRegular.arrowUpLeft;
  static const northDir = PhosphorIconsRegular.arrowUp;
  static const southDir = PhosphorIconsRegular.arrowDown;

  // ── Contacts ───────────────────────────────────────────────────────────────
  static const contacts = PhosphorIconsRegular.addressBook;

  // ── Laptop Mac ────────────────────────────────────────────────────────────
  static const laptopMac = PhosphorIconsRegular.laptop;

  // ── Rate review / review ──────────────────────────────────────────────────
  static const review = PhosphorIconsRegular.star;

  // ── Fact check ───────────────────────────────────────────────────────────
  static const factCheck = PhosphorIconsRegular.clipboardText;

  // ── Exit ─────────────────────────────────────────────────────────────────
  static const exitToApp = PhosphorIconsRegular.signOut;
  static const logout = PhosphorIconsRegular.signOut;

  // ── Mark as read / unread helpers ─────────────────────────────────────────
  static const markChatRead = PhosphorIconsRegular.checkCircle;
  static const markChatUnread = PhosphorIconsRegular.circleHalf;

  // ── Misc ──────────────────────────────────────────────────────────────────
  static const download2 = PhosphorIconsRegular.downloadSimple;
  static const print = PhosphorIconsRegular.printer;
  static const recycle = PhosphorIconsRegular.recycle;

  // ── Bedtime / Night ───────────────────────────────────────────────────────
  static const bedtime = PhosphorIconsRegular.moon;

  // ── Water / Pool ─────────────────────────────────────────────────────────
  static const swim = PhosphorIconsRegular.swimmingPool;

  // ── Volunteer activism ───────────────────────────────────────────────────
  static const volunteerActivism = PhosphorIconsRegular.handHeart;
  static const volunteerActivismFill = PhosphorIconsFill.handHeart;

  // ── Person add alt ───────────────────────────────────────────────────────
  static const personAdd = PhosphorIconsRegular.userPlus;
  static const personRemove = PhosphorIconsRegular.userMinus;

  // ── Insights / analytics ─────────────────────────────────────────────────
  static const insights = PhosphorIconsRegular.trendUp;

  // ── Forward 10 / replay ──────────────────────────────────────────────────
  static const replay = PhosphorIconsRegular.arrowCounterClockwise;

  // ── Person search ─────────────────────────────────────────────────────────
  static const personSearchIcon = PhosphorIconsRegular.userFocus;

  // ── Waving hand (specifically for greetings) ─────────────────────────────
  static const wavingHand = PhosphorIconsRegular.handWaving;
  static const wavingHandFill = PhosphorIconsFill.handWaving;

  // ── Cloud upload (generic save-to-cloud) ─────────────────────────────────
  static const cloudUpload = PhosphorIconsRegular.cloudArrowUp;

  // ── Celebrations / confetti ───────────────────────────────────────────────
  static const confetti = PhosphorIconsRegular.confetti;

  // ── Sign Language (approximation) ────────────────────────────────────────
  static const signLang = PhosphorIconsRegular.handWaving;

  // ── Explore outlined ─────────────────────────────────────────────────────
  static const exploreOutlined = PhosphorIconsRegular.compass;
}
