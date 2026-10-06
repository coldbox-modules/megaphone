# v1.1.0-rc.1 (unreleased candidate)

## Notification backend expansion

- Recipient-owned Notification Center APIs: authorized queries/counts, stable cursors, read snapshots, archive state, no-send history imports, and bounded retention.
- Ordered recipient preference scopes with independent channels and per-type device exclusions.
- Durable event/delivery storage with transactional enqueueing, leases, transport fencing, retries, ambiguous acceptance, and audited operator recovery.
- Owned encrypted web-push subscriptions, renewal/disconnection, per-device delivery, response classification, and optional SDK installation.
- Replay admission using persisted occurrence timestamps; safe terminal diagnostic cleanup with trusted query constraints and atomic retirement callbacks.

## Upgrade requirements

Existing direct notification/provider APIs remain available. New persistence capabilities require explicitly applying the ordered module migrations to the consumer's transaction-compatible datasource. Configure the queue adapter, preference scopes, visibility/eligibility callbacks, retention/replay policy, and worker recovery when adopting durable delivery. Web push additionally requires subscription encryption configuration, push credentials, the optional SDK, and browser/service-worker integration supplied by the consumer.

Do not infer migration of an existing application's history, preferences, or pending deliveries from installing this module. Consumers must define no-send import identities, a cutover boundary, one delivery owner, and acceptance-preserving rollback. Authentication/account-access mail ownership remains a consumer decision; CommuniArts keeps it outside Megaphone.

## Verification and release status

Focused module database tests have run on Lucee 5.4 and consumer integration tests on BoxLang 1.18. Broader engine matrices, actual push providers/devices, and deployment readiness are not established by those runs. This section describes the unpublished 1.1.0-rc.1 candidate. Artifact installation is verified locally; publication and consumer dependency adoption remain pending. Do not pin a consumer to an unpublished version or represent a development link as release adoption.

# v1.0.4
## 19 Apr 2024 — 16:28:17 UTC

### fix

+ __SlackProvider:__ Use default route object if none is returned
 ([979619c](https://github.com/coldbox-modules/megaphone/commit/979619c5545a6778285eec1f7763f43b55f5cf16))


# v1.0.3
## 18 Apr 2024 — 15:42:53 UTC

### fix

+ __BaseProvider:__ Only invoke routing methods if they exist
 ([dff711c](https://github.com/coldbox-modules/megaphone/commit/dff711c5c916fc34646b6b940245e94778518012))

### other

+ __\*:__ chore: Update changelog
 ([f2dbca4](https://github.com/coldbox-modules/megaphone/commit/f2dbca4cdaf8624a77b6ed35c4bf320b4add45b8))
