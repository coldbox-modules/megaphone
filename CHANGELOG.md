# v1.0.5
## 14 Oct 2026 — 00:22:34 UTC

### other

+ __\*:__ fix: load Web Push through Adobe application classpaths
 ([a5f7638](https://github.com/coldbox-modules/megaphone/commit/a5f763839c77729f0f973ef9c554e017efe593ad))
+ __\*:__ fix: preserve nullable snapshots and queue backoff on Adobe
 ([ff74b71](https://github.com/coldbox-modules/megaphone/commit/ff74b71ce3799005b39ad70b5e8e252b0c8d0911))
+ __\*:__ fix: support Adobe receipt scoping and SDK classpaths
 ([fe14bbc](https://github.com/coldbox-modules/megaphone/commit/fe14bbc8c3daf192a5e850bb7e95a0bb8cb7e13f))
+ __\*:__ fix: invoke BoxLang shallow copying without engine-specific syntax
 ([0eb4cfc](https://github.com/coldbox-modules/megaphone/commit/0eb4cfcbf357cf4b5a60404c736302b052454db9))
+ __\*:__ fix: defer BoxLang shallow-copy syntax until runtime
 ([4dc60c5](https://github.com/coldbox-modules/megaphone/commit/4dc60c576b7ddbef88acb807fc082e6a8c03f2f5))
+ __\*:__ fix: keep BoxLang notification copying compilable on Adobe
 ([f73d4e2](https://github.com/coldbox-modules/megaphone/commit/f73d4e2ec54b351a27c1b42ba8b86423c6abccfb))
+ __\*:__ feat: add durable notifications and recipient inbox APIs ([bb6638f](https://github.com/coldbox-modules/megaphone/commit/bb6638f8b467c8ce7847d37c7afcbd3664d7f741))


# v1.1.0 (pending release)

## Requirements

- JDK 11 or newer is the supported baseline. Module test servers and CI use JDK 11, with no JDK 8 matrix entry.

## Added

- Bundled cbq queue adapter and delivery job, enabled by default with connection and queue defaults and per-call `connection` and `queue` overrides. The adapter uses the Provider on a registered cbq connection, uses cbq's connection, queue, and worker defaults, and leaves Provider and worker registration to the application. Known safe retry decisions use cbq release/backoff; custom adapters remain supported.

- Notification inbox APIs with recipient access checks, stable cursors, read snapshots, archive state, history imports, and retention.
- Preferences by scope and channel, including device exclusions for each notification type.
- Durable events and deliveries with transactional queue jobs, claim tokens, retries, acceptance tracking, and operator recovery history.
- Encrypted push subscriptions, renewal and disconnect support, per-device delivery, response handling, and a pinned Web Push SDK JAR dependency installed by CommandBox.
- Event replay cutoffs and cleanup callbacks for keeping external references and retirement receipts.

## API alignment

- Grouped delivery, queue, storage, preference, and Web Push models into dedicated folders while retaining the existing WireBox names.

- The cbq notification adapter implements `INotificationQueue`, including optional connection and queue overrides.

- Model instances and push collaborators use WireBox method providers; application overrides keep their constructor dependencies when captured data is configured.

- NotificationPlan defaults its event and deliveries to empty values, so saved plans can be restored with a no-argument constructor.

- cbq is an optional application dependency. Using the cbq adapter without cbq throws `Megaphone.Queue.MissingCBQ`; synchronous notifications, custom adapters, and polling do not require it.

- Queue configuration uses `queue` settings, with `defaultConnection` and `defaultQueue` for cbq routing.

- Durable planning and queueing now use NotificationService, notification instances/mappings, notifiables, registered providers, and delegates.
- Added typed plans, publications, delivery/preparation/recovery results, keyset cursors, module storage configuration, and lazy Web Push infrastructure.
- Preferences and subscriptions now use dedicated public services; stored columns and delivery identities are retained.
- Restored released read-timestamp replacement behavior and added explicit if-unread operations.
- Added an additive notification mapping migration and documented the RC data upgrade boundary.

## Fixed

- MySQL delivery timestamps keep fractional seconds so immediately due work stays due.
- Adobe receipt checks accept an explicit false decision, and push reflection uses Java arrays supported by both engines.
- CI installs the declared push SDK dependency and runs the persistence specs against MySQL with the correct module mappings.

## Upgrading

Your existing notification and provider APIs still work. To use the new storage features, apply the module migrations in order to the same datasource as your application transaction. Megaphone includes a default cbq adapter; install cbq in your application and configure a registered connection and queue using your chosen Provider. Apply cbq's queue migrations when using its database Provider. You'll need to configure preference scopes, access and eligibility callbacks, retention and replay settings, and worker recovery. For web push, add subscription encryption keys, push credentials, Java 11+, and your browser and service-worker integration.

Installing the module doesn't import your existing history, preferences, or pending deliveries. Plan the handoff from your old delivery owner, keep stable import IDs, and make sure rollback won't resend work that's already been accepted. You can decide separately whether Megaphone handles authentication and account-access mail.

## Validation

Local API alignment checks passed: 206 module regressions on MySQL with four existing ColdBox 6 skips; 59 PostgreSQL checks; module migration rollback/reapplication; 212 focused CommuniArts checks across 41 bundles; and 1,143 Vitest checks. Clean installation, an upgrade with existing RC notification data, and repeated migrations were verified in disposable databases. Formatting and artifact inspection passed. Earlier candidate engine-matrix results do not validate this refactor. Hosted CI, browser matrices, real-provider/device checks, publication, and deployment remain deferred.

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
