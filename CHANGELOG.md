
## [unreleased] — 2026-05-24

### Fixed
- **Services screen: only 1 listing shown** — Root cause was Firestore Security Rules missing
  a rule for the `local_services` collection. Firestore's default-deny policy blocked all
  client SDK reads; Admin SDK bypassed rules (hence 221 docs visible in diagnostics).
  - Created new ruleset `d8d41f3e-e9fd-43b1-853c-dab6538c30e3` with `local_services` rule
  - Applied ruleset to `cloud.firestore` release via Firebase Rules REST API PATCH
    (`UpdateReleaseRequest` wrapper with `release` + `updateMask` fields — previous
    attempts used wrong body structure, causing HTTP 400)
  - Rule grants authenticated read/create; update/delete only to listing owner
  - Endorsements sub-collection: read for any auth'd user, write only to matching uid
