# Changelog

All notable changes to FS25_ProStaffCoOp will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Changelog tracking for this mod begins **2026-08-22** under the suite-wide ruling
(see the ecosystem ledger, entry for Arissani and Wizard). Prior history lives in
the repo's git history and README.

---

## [Unreleased]

### Added
- Changelog file established (suite ruling 2026-08-22).

### Fixed
- **Co-Op level purchases, disease flushes and the admin clear now work for players who join a server.** On a joined client the request reached the server empty, so the purchase (and the flush and the clear) silently did nothing; the host was never affected. The requests now carry the farm the way the shared transport reads it, and the server still applies them only for the farm the requesting player belongs to; a spectator's request is refused. One press buys one level, as on a host.

## [1.0.0.2] - 2026-08-22

- First entry under changelog tracking.
