Installation: `box install megaphone`

## Recipient-owned inbox APIs

`DatabaseNotificationService@megaphone` supports recipient-owned lookup, unread
counts, read snapshots, imports, and bounded retention. Existing retrieval
arguments remain compatible. The `HasDatabaseNotifications` delegate also exposes
lookup, counts, snapshots, and pruning using its parent as the recipient.

Apply the additional inbox-state migration before enabling
`properties.inboxState = true` on a database channel. It adds nullable
`archivedDate` and `groupKey` columns and recipient/order/group indexes. Existing
channels default to the original schema, and ordinary retrieval does not require
the new columns. Custom table consumers must apply equivalent schema changes to
their configured `properties.table`. For PostgreSQL UUID notification IDs, set
`properties.idSqlType = "other"`; the default string binding remains compatible
with string ID columns.

```cfc
var inbox = wirebox.getInstance( "DatabaseNotificationService@megaphone" );
var visible = ( query ) => query.whereIn( "groupKey", authorizedGroupKeys );
var page = inbox.getNotifications(
    notifiable = currentUser,
    constraints = visible,
    archiveMode = "active",
    initialPage = 1,
    maxRows = 25
);
var unread = inbox.countUnreadNotifications(
    notifiable = currentUser, constraints = visible, archiveMode = "active"
);
var ids = inbox.snapshotIds(
    notifiable = currentUser, constraints = visible, archiveMode = "active"
);
inbox.markSnapshotAsRead( notifiable = currentUser, ids = ids, constraints = visible );
```

Visibility constraints are grouped inside recipient ownership and run before
pagination/counting. Loaded notifications retain their constraint for later
mutation. `getNotification` returns null for a missing, foreign, or unauthorized
ID. Applications must supply current authorization constraints; group metadata
alone does not grant access. `archiveMode` accepts `all` (the compatibility
default), `active`, or `archived`. Notification `archive()` and `unarchive()`
preserve read state. Archived entries remain stored and can be restored.
Read/archive listing filters and page boundaries do not invalidate a loaded
notification after its state changes; its recipient and visibility constraints
still guard subsequent mutations and state refreshes. Cursor `configureQuery`
callbacks constrain both listing and mutation queries by default and must only
configure the supplied query, without external side effects. Pass
`constrainMutations=false` only for presentation filters that should not govern
later mutations; authorization constraints must retain the default.

Bulk read snapshots contain the IDs visible when captured. Recheck authorization
when applying them; later arrivals are excluded. Repeated reads preserve the
original read date. Existing cursor-wide mutation APIs remain available for
existing consumers, but use snapshots when new arrivals must survive a bulk read.

`importNotification(notifiable, id, type, data, createdDate, readDate, channelName,
groupKey, archivedDate)` stores history without routing any external channel.
It preserves a preexisting row on repeat, and rejects an ID owned by another
recipient or type. Applications must verify their source-to-ID mapping and payload
consistency before import, and call it in their import transaction.

`PreferenceStore.importChoice(notifiable, notificationType, scopeKey, channel,
choice)` inserts a missing explicit preference without replacing an existing
choice, including under concurrent inserts. Inherit creates no row. Migration
callers must retain their own import receipt so a later user choice of Inherit
is not recreated by rerunning a backfill. This API does not dispatch deliveries.

`DeliveryStore.importDelivery(intent, history)` imports durable delivery state
without routing or provider I/O. Intent uses enqueue's identity/routing fields;
history supplies state, attemptCount, createdDate, optional settledDate, reason
and providerReference. Accepted imports require a bounded positive-evidence
reference. Ambiguous imports remain outside automatic due work. Existing
identities retain their current state on rerun; attempts are not fabricated.
Consumers must validate source evidence, stop the competing owner and retain
source attempt/audit references. Importing queued work makes it eligible for
recovery after commit, so it must occur within the coordinated cutover boundary.
`pruneNotifications(notifiable, keep=1000, batchSize=200, channelName="database")`
removes at most one batch of the oldest entries beyond the cap, including archives.
Repeat scheduled calls until the excess is cleared. This API does not prune
domain history, delivery attempts, or deduplication records.

## Preference resolution

`PreferenceResolver@megaphone.resolve(defaults, scopes)` accepts channel boolean
defaults and ordered scopes from least to most specific. Each scope has a `key`
and `choices` mapping channels to `inherit`, `on`, or `off`. It returns each
channel's effective `enabled` flag and `source` key without changing input.
Scope names and authorization belong to the application. Optional persistence
is provided by `PreferenceStore@megaphone` after applying its migration.

`selectDevices(devices, excludedIds)` selects active registrations by stable ID,
removes duplicates and exclusions, and includes future registrations naturally.
Device enrollment, persistence, and delivery are separate from this pure resolver.

`PreferenceStore.saveChoice(notifiable, notificationType, scopeKey, channel,
choice)` stores `on`/`off` or removes the exact owned choice for `inherit`.
`choices(notifiable, notificationType, scopeKeys)` returns the requested scopes in
the supplied order, including empty choices for inherited scopes.
`configuration(notifiable, notificationType, defaults, scopeKeys)` returns both
the scopes and resolved effective values. The application must authorize catalog
types and scope keys before calling these APIs; arbitrary scope strings grant no
access. `deleteRecipient(notifiable)` removes only that recipient's choices.

`PreferenceStore.pruneChoices(constraints, limit=100)` removes a bounded batch
of stale choices across recipients. Supply a trusted QueryBuilder constraint
callback identifying obsolete scopes; the module does not know which application
resources exist. Candidates use deterministic composite-key ordering and are
rechecked under row locks before deletion. Limits must be integers from 1 to
1,000. Preserve live and account defaults in the callback. This maintenance API
must not be exposed as a user-authorized arbitrary query or scope deletion.

## Owned push registrations

Apply the subscriptions and device-exclusions migrations before using
`SubscriptionStore@megaphone`. `register(notifiable, endpointHash, sealedData,
label, existingId, expiresDate)` requires a SHA-256 endpoint hash and encrypted
material. Use `existingId` only for an owned registration renewal; it preserves
device exclusions. A subscription moving to another account retires its old
registration, scrubs its encrypted material, and creates a separate owned ID.

`registrations(notifiable, activeOnly=true, clock=now())` returns safe device metadata without
endpoints, hashes, or encrypted keys. Internal dispatch uses
`activeRegistration(notifiable, id, clock)` to retrieve an active, unexpired
registration; keep this result out of client responses and logs. Owned `rename`
and `disconnect` return false for a missing or foreign ID.
`setExcluded(notifiable, notificationType, deviceId, excluded)` and
`excludedIds(notifiable, notificationType)` maintain per-type exclusions.
`pruneInactive(beforeDate, limit=100)` removes retired registrations and their
exclusions in bounded batches. `deleteRecipient` removes that owner's records.
Disconnect registrations on logout and account switching; the store does not
observe application authentication events automatically.

The active-only list excludes expired subscriptions using the same clock boundary as dispatch. Use `activeOnly=false` to include expired and disconnected registrations in a device-management screen; the stored active flag alone does not prove a subscription is unexpired.

`SubscriptionCipher(activeKeyId, keys)` seals JSON subscription material with
AES-256-GCM. Each configured key is a base64-encoded 32-byte storage key. Supply
the same nonempty recipient-and-origin context to `seal(subscription, context)`
and `unseal(sealedData, context)`. Retain old key IDs while their records exist;
new writes use the active key. Storage encryption keys are separate from VAPID
keys. Validation of browser subscription fields remains the enrollment
boundary's responsibility.

`WebPushResponsePolicy.classify(statusCode, retryAfter="", clock=now())` returns
dispatch outcomes with safe reason codes and `retireSubscription`. HTTP 201/202
indicate service acceptance, not user delivery. HTTP 404/410 retire the target;
429 and server errors are retryable with bounded retry dates. Timeouts,
redirects, and unexpected success codes remain ambiguous. The policy never
retains response bodies or endpoint URLs. A transport exception after sending
must remain ambiguous through `DeliveryDispatcher`; this classifier applies
only when a completed HTTP response is available.

## Optional Java Web Push transport

`WebPushTransport` requires Java 11+ and the optional
[zerodep-web-push-java SDK](https://github.com/st-user/zerodep-web-push-java).
Install the pinned SDK explicitly from the module directory:

```sh
box task run taskFile=tasks/InstallWebPushSDK.cfc
```

The task downloads version 2.1.5 from Maven Central and verifies SHA-256
`1337acba24004f2a702275b676eb3862e402c8775d3031b26464f0b18d3ba989`
before writing the JAR under `resources/java/webpush`. Repeated runs verify the
installed file. Include this optional installation in the deployment build when
push is enabled. Normal Megaphone installation does not download the SDK.

Load that directory with the consumer's Java loader and supply its `create`
class factory, the SDK's VAPID key pair, a contact subject (`mailto:` or HTTPS),
and explicitly trusted push-service DNS hosts to `new WebPushTransport(...)`.
Trusted hosts allow exact names or `*.example.com` subdomain patterns; the latter
does not include the parent domain. Do not derive this allowlist from browser
input. The default client disables redirects and uses bounded connect/request
timeouts. An optional `httpClient` constructor argument supports a configured
consumer transport or a provider fixture; that client must preserve the same
redirect, timeout, and no-automatic-retry guarantees.

`prepare(subscription, payload, ttlSeconds=3600)` performs no external I/O. It
validates HTTPS endpoints, keys and single-record UTF-8 payload size, then uses
the SDK for VAPID signing and `aes128gcm` encryption. TTL accepts zero through
seven days. Build this request during eligibility preparation, before marking
transport started; recheck the registration and notification authorization in
the application callback. Keep the request internal because its URI and headers
contain private subscription and authorization material.

After the durable dispatcher's transport-start marker,
`sendPrepared(request)` sends once and discards the response body. It returns
`WebPushResponsePolicy` outcomes or ambiguous acceptance for transport errors.
The application retires an owned registration when `retireSubscription=true`;
failure or expiry of one registration must not cancel another device's work.
This transport does not create inbox entries or change preferences.

The optional `tests.specs.integration.WebPushPreparationSpec` bundle verifies
actual SDK request preparation and provider-boundary fixtures after installing
the SDK. It sends nothing to real devices. Real push providers, service workers,
permission/enrollment UX, and device delivery need separate acceptance evidence.

## Durable event identities

Apply the independent `megaphone_events` migration to use `EventStore@megaphone`.
`record(namespace, eventKey, version, type, payload, payloadHash, createdDate)`
stores an immutable content snapshot and returns the existing event on replay.
The application supplies a stable hash of its canonical domain payload. Reusing
an identity with another type or hash raises `Megaphone.Events.IdentityConflict`.
The unique database constraint protects concurrent attempts. Record events in the
same datasource and transaction as the domain change; this API does not start an
independent transaction or call external providers. Optional constructor
`properties.table` and `properties.queryOptions` configure storage.

Event identity is separate from recipient inbox rows, so inbox pruning cannot
make an event new again. `find(id)` returns the snapshot or null. Applications
must retain identities for their replay window; the event store is not a user
inbox and does not grant access to notification content. Delivery/outbox routing
is a separate capability and is not implicitly performed by `record`.

## Durable delivery and dispatch

The delivery and attempt migrations are optional for existing synchronous
consumers. `DurableNotificationService@megaphone.publish(event, intents,
queueAdapter)` records a domain event and its recipient/channel/device work in
one transaction. An intent supplies `recipientType`, `recipientId`, `channel`,
optional `deviceId`, explicit `enabled`, `routingData`, `routingHash`, and optional
`availableDate`. Disabled channels are stored as suppressed; enabling them later
does not revive that work. A repeated event returns its existing work without
adding newly eligible recipients or channels.

An optional queue adapter implements `enqueue(delivery)` and must persist a
reference job in the same datasource and transaction. It must not call an
external provider. Queue insertion failures roll back publication, even when the
caller catches the error within its domain transaction. Without an adapter, the
durable rows remain available through `DeliveryStore.due(limit, clock)` for a
bounded scheduler. Duplicate queue jobs are safe because claiming is fenced.

`due(limit=100, clock=now(), constraints)` accepts an optional trusted query
callback applied before ordering and the batch limit. Queue adapters can exclude
deliveries with an existing live queue reference so those jobs do not repeatedly
occupy a recovery batch and starve missing jobs. Keep that queue-specific query in
the adapter, and recheck under the adapter's concurrency guard before enqueueing;
the candidate query alone does not prevent concurrent schedulers.

`DeliveryStore@megaphone` offers `enqueue`, `find`, `forEvent`, `claim`,
`startTransport`, `complete`, `due`, `attempts`, and `recoverExpired`. Its optional
constructor properties configure `table`, `attemptsTable`, `eventsTable`, and
`queryOptions`. Event/delivery stores and the queue must use the domain
transaction's datasource. Queue jobs carry delivery IDs, not serialized user
objects or credentials.

`DeliveryDispatcher@megaphone.dispatch(id, eligibility, sender, leaseSeconds=60,
maxAttempts=5, retrySeconds=30)` claims work and runs application callbacks:

- `eligibility(delivery)` prepares content and rechecks current access,
  preferences, subscription ownership, feature availability, and source revision
  immediately before transport. It returns `status` as `ready`, `suppressed`,
  `deferred`, or `permanent`, plus optional safe reason/retry date and prepared
  content. The module does not assume an application's authorization model.
- `sender(delivery, prepared)` sends using the configured channel adapter and
  returns `outcome` as `accepted`, `retryable`, `permanent`, or `ambiguous`, plus
  optional provider reference, safe reason, and retry date. `retryable` requires
  evidence of rejection before acceptance; an uncertain timeout is ambiguous.

The transport marker must succeed before I/O. Lease expiry before that marker
permits retry with a new token; the previous worker cannot start transport.
Expiry or an exception after the marker leaves acceptance ambiguous and blocks
automatic resends. A late result from the same ambiguous lease can still record
acceptance. Reconciliation must establish a definitive outcome before retrying;
provider acceptance never implies user receipt or read state. Pre-transport
feature pauses/preparation failures do not consume the actual transport limit.
`attemptCount` counts claims, while `transportCount` counts transport starts.

`recoverExpired(limit=100, clock)` reclassifies expired processing rows in bounded
batches. Run it alongside the due-work scheduler so a lost queue job cannot
strand work. Sender callbacks must not start a new domain transaction around
network I/O; claim/policy state is committed before invoking the provider.

`reconcileAccepted(id, acceptance, clock=now())` settles a delivery from a verified
receipt, including late acceptance or acceptance imported from a former delivery
owner. The local, no-I/O callback receives the immutable delivery and returns
`{ accepted: false }` or `{ accepted: true, providerReference: "receipt-id" }`.
The consumer must verify the receipt belongs to that delivery before returning
true. Confirmed acceptance fences queued/running work without another send;
existing attempt outcomes are retained rather than attributed to a newer attempt.
This backend API is not an unauthenticated receipt endpoint.

`pruneAttempts(beforeDate, limit=200)` deletes diagnostics only for terminal
deliveries and retains the durable provider reference. `pruneResolvedEvents(
eventsBefore, deliveriesBefore, limit=100)` deletes event identities and their
work only when the event is beyond the application's replay window and every
delivery is terminal and old enough. Pending or ambiguous work and its evidence
are protected. Applications must enforce their replay window before publishing
old domain events; use `importNotification` for history instead of publication.
Neither cleanup API deletes user inbox rows or domain audit history.

Use scheduled, configurable cutoffs, for example 90 days for terminal attempt
diagnostics and 365 days for resolved event identities, with the latter strictly
beyond the allowed domain-event replay period. The inbox's count cap is separate.

Config:
```cfc
// config/modules/megaphone.cfc
component {

	function configure() {
		return {
			"channels": {
                // this is the unique name for the channel
				"database": {
                    // providers can be used multiple times with different properties, like cbq connections & providers
                    // currently, only the database provider exists
					"provider": "DatabaseProvider@megaphone",
					"properties": {
                        // this is the default table name
						"tableName": "megaphone_notifications",
						"datasource": "megaphone"
					}
				}
			}
		};
	}

}
```

There is one interface that needs to be adhered to (`implements` keyword optional) — `INotifiable`:
```cfc
interface displayName="INotifiable" {

    public string function getNotifiableId();
    public string function getNotifiableType();

}
```
That goes on any CFC that will be sent notifications.
(In most applications it is just `User`, but it could be more depending on your use case like `Team` or `Company`)

Your application's Notifications extend `megaphone.models.BaseNotification`:

```cfc
// StockRebalancingCompleteNotification.cfc
component extends="megaphone.models.BaseNotification" accessors="true" {

	property name="stockSymbol";
    property name="completionTimestamp";

	public array function via( required any notifiable ) {
		return [ "database" ];
	}

    public struct function toDatabase( required any notifiable ) {
        return {
            "stockSymbol": getStockSymbol(),
            "completionTimestamp": getCompletionTimestamp()
        };
    }

}
```

The first required method to implement is `via`.  It receives a `notifiable` and returns an array of channels to send the notification to.

```cfc
public array function via( required any notifiable ) {
    return [ "database" ];
}
```

In this example, every notifiable gets this notification sent to the database, but you could customize that per notifiable.
This can be customized based on the notifiable type, e.g. Team notifications go to Slack channels where User notifications go to SMS and the database.

```cfc
public array function via( required any notifiable ) {
    return notifiable.getNotifiableType() == "Team" ? [ "slack" ] : [ "sms", "database" ];
}
```

This can also be customized based on the notifiable id, e.g. User A has requested email notifications where User B requested email and SMS notifications.
```cfc
public array function via( required any notifiable ) {
    return notifiable.getNotificationChannels(); // [ "email" ] for one, [ "email", "sms" ] for another, etc.
}
```

After implementing `via`, you need to implement a `to{Provider}` method for each Provider.
For instance, if the `DatabaseProvider` is an option, than a `toDatabase` method needs to be implemented.

```cfc
public struct function toDatabase( required any notifiable ) {
    return {
        "stockSymbol": getStockSymbol(),
        "completionTimestamp": getCompletionTimestamp()
    };
}
```

Only one `toDatabase` method would need to be implemented, regardless of how many channels use the `DatabaseProvider`.
For example, if your `DatabaseProvider` channel was called `db`, your `via` method would return `[ "db" ]` and you would implement a `toDatabase` method.

(These methods also receive the `notifiable` instance in case it is needed to generate the notification data for the Provider.)

Notifications are sent using the `NotificationService`, often aliased as `megaphone`.

```cfc
// handlers/StockRebalancing.cfc
component {

    property name="megaphone" inject="NotificationService@megaphone";

    function create( event, rc, prc ) {
        // ...
        var notification = getInstance( "StockRebalancingCompleteNotification" )
        notification.setStockSymbol( "APPL" );
        notification.setCompletionTimestamp( now() );
        megaphone.notify( auth().user(), notification );
        // ...
    }

}
```

For those of you allergic to calling `getInstance` (😜), you can also pass a string name and a struct of properties:
```cfc
// handlers/StockRebalancing.cfc
component {

    property name="megaphone" inject="NotificationService@megaphone";

    function create( event, rc, prc ) {
        // ...
        megaphone.notify(
            auth().user(),
            "StockRebalancingCompleteNotification",
            { "stockSymbol": "APPL", "completionTimestamp": now() }
        );
        // ...
    }

}
```

Another way to send a Notification is by adding the `SendsNotifications@megaphone` delegate to a `Notifiable` instance:
```cfc
component name="User" delegates="SendsNotifications@megaphone" accessors="true" {

    property name="id";

    public string function getNotifiableId() {
        return getId();
    }

    public string function getNotifiableType() {
        return "User";
    }

}
```
Then you can call a `notify` method on the `Notifiable` instance.
```cfc
// handlers/StockRebalancing.cfc
component {

    property name="megaphone" inject="NotificationService@megaphone";

    function create( event, rc, prc ) {
        // ...
        auth().user().notify(
            "StockRebalancingCompleteNotification",
            { "stockSymbol": "APPL", "completionTimestamp": now() }
        );
        // ...
    }

}
```
Lastly, there's some specific information for Database notifications.

First, here's the migration file (it will also be av available in the module under `resources/database/migrations`):
```cfc
component {

    function up( schema ) {
        schema.create( "megaphone_notifications",  ( t ) => {
            t.guid( "id" ).primaryKey();
            t.string( "type" ); // notification wirebox id
            t.string( "notifiableId" );
            t.string( "notifiableType" );
            t.longText( "data" ); // serializeJSON of what is returned from `toDatabase`
            t.timestamp( "readDate" ).nullable();
            t.timestamp( "createdDate" ).withCurrent();

            t.index( "type" );
            t.index( "readDate" );
            t.index( name = "idx_megaphone_notifications_notifiable_index", columns = [ "notifiableId", "notifiableType" ] );
        } );
    }

    function down( schema ) {
        schema.dropIfExists( "megaphone_notifications" );
    }

}
```
MySQL Server sytanx:
```sql
CREATE TABLE ` megaphone_notifications` (
    `id` NCHAR(36) NOT NULL,
    `type` VARCHAR(255) NOT NULL,
    `notifiableId` VARCHAR(255) NOT NULL,
    `notifiableType` VARCHAR(255) NOT NULL,
    `data` LONGTEXT NOT NULL,
    `readDate` TIMESTAMP NULL DEFAULT NULL,
    `createdDate` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `pk_megaphone_notifications_id` PRIMARY KEY (`id`),
    INDEX `idx_megaphone_notifications_type` (`type`),
    INDEX `idx_megaphone_notifications_readDate` (`readDate`),
    INDEX `idx_megaphone_notifications_notifiable_index` (`notifiableId`, `notifiableType`)
)
```
and in SQL Server syntax:
```sql
CREATE TABLE [megaphone_notifications] (
    [id] uniqueidentifier NOT NULL,
    [type] VARCHAR(255) NOT NULL,
    [notifiableId] VARCHAR(255) NOT NULL,
    [notifiableType] VARCHAR(255) NOT NULL,
    [data] VARCHAR(MAX) NOT NULL,
    [readDate] DATETIME2,
    [createdDate] DATETIME2 NOT NULL CONSTRAINT [df_megaphone_notifications_createdDate] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [pk_megaphone_notifications_id] PRIMARY KEY ([id]),
    INDEX [idx_megaphone_notifications_type] ([type]),
    INDEX [idx_megaphone_notifications_readDate] ([readDate]),
    INDEX [idx_megaphone_notifications_notifiable_index] ([notifiableId], [notifiableType])
)
```

There are two ways to retrieve notifications from the database.
First, the non-delegated way, injecting the `DatabaseNotificationService`

```cfc
component {

    property name="databaseNotificationService" inject="DatabaseNotificationService@megaphone";

    function index( event, rc, prc ) {
        // ...
        var cursor = variables.databaseNotificationService.getUnreadNotifications(
            notifiable = auth().user(),
            channel = "database" // default is "database",
            initialPage = 1 // default is 1,
            maxRows = 25 // default is 25
        );
        // ...
    }

}
```
Or, the delegated way.
First, add the delegate:
```cfc
component name="User" delegates="HasDatabaseNotifications@megaphone" accessors="true" {

    property name="id";

    public string function getNotifiableId() {
        return getId();
    }

    public string function getNotifiableType() {
        return "User";
    }

}
```
Then use it:
```cfc
component {

    function index( event, rc, prc ) {
        // ...
        var cursor = auth().user().getUnreadNotifications(
            channel = "database" // default is "database",
            initialPage = 1 // default is 1,
            maxRows = 25 // default is 25
        );
        // if you want all the defaults:
        var cursor = auth().user().getUnreadNotifications();
        // ...
    }

}
```
A cursor is for paginating through results and for interacting with the entire collection at once.
```cfc
cursor.getPagination(); // { "maxRows": 25, "totalPages": 1, "offset": 0, "page": 1, "totalRecords": 5 }
cursor.getResults(); // [ DatabaseNotification ]
for ( var notification in cursor.getResults() ) {
    notification.getMemento(); // { id, type, notifiableType, notifiableId, data, readDate, createdDate }
    notification.getData(); // struct / already deserialized
    notification.getType(); // string — notification wirebox id
    notification.markAsRead( readDate = now() ); // sets and saves the readDate, default = now()
    notification.delete(); // deletes the notification from the database
}
cursor.hasPrevious(); // boolean
cursor.previous(); // loads previous page from database
cursor.hasNext(); // boolean
cursor.next(); // loads next page from database
cursor.markAllAsRead( readDate = now() ); // marks all as read, not just current page. default = now()
cursor.deleteAll(); // deletes all, not just current page
```

### Keyset inbox pages

`DatabaseNotificationService.getNotificationSlice()` returns `{ results, nextCursor, hasMore }`. Pass `nextCursor` as `afterCursor` for the next page. Ordering is newest `createdDate`, then descending ID. Inserts ahead of the boundary do not repeat entries, and deleting the boundary row does not invalidate continuation. The cursor is recipient-bound, but is not an authorization credential: current recipient ownership, visibility constraints, archive mode, and unread filters are applied to every page. Reset the cursor when filters change. A fresh first page includes new arrivals.

This optional API requires the database provider's trusted `cursorTimestampExpression` configuration to return timestamp text in `yyyy-MM-dd HH:mm:ss[.fraction]` form without losing database precision. Set `cursorTimestampSqlType` to the JDBC binding type your adapter needs. For PostgreSQL, configure `cursorTimestampExpression = 'CAST("createdDate" AS TEXT)'` and `cursorTimestampSqlType = "other"`; UUID IDs also use `idSqlType = "other"`. Expressions are application configuration, never caller input. Existing offset pagination APIs remain unchanged and do not require this configuration.

Invalid or foreign-recipient cursors throw `Megaphone.Database.InvalidCursor`. Configure `cursorIdentifierPattern` when the database has a constrained ID type, such as a UUID column, so malformed cursor identifiers are rejected before JDBC conversion. Views may retain previous-page cursor boundaries for back navigation, but each request rechecks access. A cursor is a position, not a frozen copy of permission or read/archive state. Pruned entries disappear; they do not shift a numeric offset. Pending delivery and deduplication records remain independent of inbox pagination and retention.
