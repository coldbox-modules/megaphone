# v1.1.1
## 14 Oct 2026 — 20:06:04 UTC

### other

+ __\*:__ feat: add named email digests (#3) ([0eee0e4](https://github.com/coldbox-modules/megaphone/commit/0eee0e4bd36f08e396889dd3a0dd8990971215f1))


# v1.2.0

## Added

- EmailDigestProvider collects Notifications into independent named digests using `toEmailDigest()`, `notify()`, and captured notification plans.
- Immediate subscriptions create one-item batches through the same digest policy, selection, renderer, and durable email transport, with no separate ordinary-email route. Immediate-only definitions require no calendar schedule.
- EmailDigestService manages per-Notifiable Off, Immediate email, and Digest subscriptions with native ColdBox schedules and confirmed timezones.
- Durable digest subscriptions, items, batches, and event admissions preserve stable identities, deduplicate overlapping publication, and freeze membership at atomic cutoffs.
- The module ColdBox scheduler registers named digest tasks at startup and supports runtime digest and timezone registration. Native shortcuts, configuration closures, and unstarted task templates use ColdBox scheduling and timezone behavior.
- Configurable item selection keeps all eligible items by default, discards omitted pre-cutoff candidates permanently, and never carries overflow into future digests.
- `itemKey()` and `occurredAt()` helpers produce stable logical identities and integer UTC epoch milliseconds.
- Batch preparation and dispatch reuse the existing receipt-aware email delivery, claim, attempt, retry, and recovery APIs.
- Named policy and renderer contracts integrate application consent, current item eligibility, content, and digest-specific unsubscribe links. Consent and eligibility are checked again after rendering.
- NotificationPublication exposes collection admissions separately through `getCollections()`; collection is never recorded as mail acceptance.
- `reconcileNotAccepted()` permits retry of an ambiguous delivery only after authoritative nonacceptance evidence, preserving transport counts. `recoverExpired()` accepts optional maintenance constraints.

## Configuration

Configure definitions under `digests` and persistence under `storage.digests`. A definition supplies its schedule, policy, renderer, and receipt-aware email channel. Apply the additive digest migration on the same datasource as notification events and deliveries before collecting items.

Existing synchronous Notifications and ordinary immediate email continue to use their configured channels. Subscription changes apply prospectively and do not replay old collected items. See [Named email digests](docs/email-digests.md) for integration examples.

# v1.1.0

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

Release CI passed all ten engine/framework combinations: Lucee 5/6 and Adobe ColdFusion 2021/2023 with ColdBox 6/7, plus native and CFML-compatible BoxLang with ColdBox 8. The matrix uses Java 11, 17, and 21 according to each engine's requirements. Existing local verification also covered PostgreSQL persistence, migration upgrades and repeat runs, saved-plan replay, optional cbq activation, formatting, and package contents.

Real-provider/device checks and browser matrices remain separate from the module release.

# v1.0.5

This version was published by the release workflow with an incorrect patch version. Use 1.1.0 for the notification planning, queued delivery, and inbox APIs described above.

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
