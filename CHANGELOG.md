# v1.1.0 (pending release)

## Added

- Notification inbox APIs with recipient access checks, stable cursors, read snapshots, archive state, history imports, and retention.
- Preferences by scope and channel, including device exclusions for each notification type.
- Durable events and deliveries with transactional queue jobs, claim tokens, retries, acceptance tracking, and operator recovery history.
- Encrypted push subscriptions, renewal and disconnect support, per-device delivery, response handling, and an optional SDK installer.
- Event replay cutoffs and cleanup callbacks for keeping external references and retirement receipts.

## Fixed

- MySQL delivery timestamps keep fractional seconds so immediately due work stays due.
- Adobe receipt checks accept an explicit false decision, and push reflection uses Java arrays supported by both engines.
- CI installs the push SDK and runs the persistence specs against MySQL with the correct module mappings.

## Upgrading

Your existing notification and provider APIs still work. To use the new storage features, apply the module migrations in order to the same datasource as your application transaction. You'll need to configure your queue adapter, preference scopes, access and eligibility callbacks, retention and replay settings, and worker recovery. For web push, add subscription encryption keys, push credentials, the optional SDK, and your browser and service-worker integration.

Installing the module doesn't import your existing history, preferences, or pending deliveries. Plan the handoff from your old delivery owner, keep stable import IDs, and make sure rollback won't resend work that's already been accepted. You can decide separately whether Megaphone handles authentication and account-access mail.

## Validation

The release branch passed 198 tests on Lucee 5 and Adobe 2023 with ColdBox 6 and MySQL. Adobe also retained the four existing ColdBox 6 skips. The MySQL migrations passed a full rollback and reapplication. The 69 PostgreSQL database and preference checks passed too. These tests didn't send to providers. The local 1.1.0 archive also passed its content checks. Earlier consumer integration tests ran on BoxLang 1.18.

The broader engine matrix, real push providers and devices, clean installation of this stable candidate, and deployment still need verification. This package hasn't been published yet. Check ForgeBox before updating a consumer's dependency pin, and verify the installed release rather than a local development link.

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
