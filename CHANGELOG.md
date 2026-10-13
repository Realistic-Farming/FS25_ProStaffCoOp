# Changelog

All notable changes to FS25_ProStaffCoOp will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Changelog tracking for this mod begins **2026-08-22** under the suite-wide ruling
(see the ecosystem ledger, entry for Arissani and Wizard). Prior history lives in
the repo's git history and README.

---

## [Unreleased]

## [1.2.0.0] - 2026-10-12

> **This is not a final release.** It gives everyone, testers and players, new or returning, everything we have built so far, so nobody has to wait on an old version any longer. The Realistic Farming suite is far from done: we are still building and expanding every mod, and completing it could take months, possibly a year. Expect changes and rough edges along the way, and please report anything that looks wrong.

### Added
- A Pro Staff page on the Realistic Farming Esc menu: your membership, live bonuses, the twenty Co-Op levels as cards (with the current one marked), buying the next level, and the disease flush quote and run. It works on any host.
- Scrollable breed tables.

### Fixed
- The Pro Staff page and the twenty level names are translated into all 25 languages the game supports (they read English everywhere before).
- Multiplayer: buying a Co-Op level, running a disease flush and the admin clear reach the server correctly.
- The Disease Flush scouts the fields of the farm that runs it.
- Editing the HUD in the suite editor works again, and the page legend shows a plain dot between page names (a stray "Â" is gone).

### Added
- Changelog file established (suite ruling 2026-08-22).

### Fixed
- **Co-Op level purchases, disease flushes and the admin clear now work for players who join a server.** On a joined client the request reached the server empty, so the purchase (and the flush and the clear) silently did nothing; the host was never affected. The requests now carry the farm the way the shared transport reads it, and the server still applies them only for the farm the requesting player belongs to; a spectator's request is refused. One press buys one level, as on a host.

## [1.0.0.2] - 2026-08-22

- First entry under changelog tracking.
