Installation: `box install megaphone`

## Notification inboxes

You can use `DatabaseNotificationService@megaphone` to look up a recipient's
notifications, count unread items, mark a snapshot as read, import history, and
clean up old entries. The existing retrieval arguments still work. If you use the
`HasDatabaseNotifications` delegate, these methods use the parent object as the
recipient.

To add archive state and grouping, apply the inbox-state migration and set
`properties.inboxState = true` on your database channel. The migration adds
nullable `archivedDate` and `groupKey` columns and indexes for recipient, order,
and group lookups. Existing channels keep using the original schema by default.
If you use a custom `properties.table`, apply the same changes to that table.
For PostgreSQL UUID IDs, set `properties.idSqlType = "other"`. The default string
binding still works for string ID columns.

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

The `constraints` callback runs inside the recipient filter, before pagination
and counting. Loaded notifications keep that constraint for later updates.
`getNotification` returns null if the ID is missing, belongs to another recipient,
or fails your constraint. You still need to supply your application's current
authorization rules; a `groupKey` by itself doesn't grant access.

`archiveMode` accepts `all` (the existing default), `active`, or `archived`.
Calling `archive()` or `unarchive()` leaves the read date alone. Archived entries
stay in the database, so you can restore them later. Changing read or archive
state doesn't invalidate an already loaded notification just because it no
longer matches the page's display filter. Recipient and visibility checks still
apply when you update it or refresh its state.

Cursor `configureQuery` callbacks apply to both retrieval and updates by default.
Use them to configure the supplied query, without calling external services.
Set `constrainMutations=false` only for display filters that shouldn't limit later
updates. Keep the default for authorization constraints.

A read snapshot contains the IDs visible when you took it. Check authorization
again when marking those IDs as read. Notifications that arrive afterward stay
unread, and marking an item as read again preserves its original read date.
The existing cursor-wide methods are still available; use snapshots when you
want to leave new arrivals alone.

### Importing existing notifications

`importNotification(notifiable, id, type, data, createdDate, readDate, channelName,
groupKey, archivedDate)` saves history without sending anything. Running it again
leaves the existing row alone. An ID belonging to another recipient or type is
rejected. Check your source IDs and payloads before importing, and call this
method inside your import transaction.

`PreferenceStore.importChoice(notifiable, notificationType, scopeKey, channel,
choice)` adds a missing explicit choice without replacing one that's already
there, even when two imports run at once. `inherit` creates no row. Keep a record
of which choices you've imported so rerunning a backfill doesn't recreate a
choice the user has since changed to Inherit. Importing choices sends nothing.

`DeliveryStore.importDelivery(intent, history)` imports delivery state without
calling a provider. `intent` uses the same identity and routing fields as
`enqueue`; `history` supplies state, attemptCount, createdDate, and optional
settledDate, reason, and providerReference. To import accepted work, supply a
bounded reference to evidence that it was accepted. Ambiguous work stays out of
automatic retries. Repeated imports preserve the current state and don't invent
attempts.

Before importing deliveries, verify the source evidence, stop the old delivery
owner, and keep its attempt and audit references. Queued work becomes eligible
for recovery after commit, so coordinate that import with the handoff to your
new worker.

`pruneNotifications(notifiable, keep=1000, batchSize=200, channelName="database")`
removes one batch of the oldest entries above the cap, including archived entries.
Call it on a schedule until the excess is gone. It only removes inbox entries;
domain history, delivery attempts, and event identities have their own retention.

## Notification preferences

`PreferenceResolver@megaphone.resolve(defaults, scopes)` takes channel defaults
and scopes ordered from least to most specific. Each scope has a `key` and a
`choices` struct with `inherit`, `on`, or `off` for each channel. The result gives
you the effective `enabled` value and the `source` key for each channel. Your
inputs aren't changed. You choose the scope names and check access to them.
If you want to store those choices, apply the preference migration and use
`PreferenceStore@megaphone`.

`selectDevices(devices, excludedIds)` picks active registrations by stable ID and
removes duplicates and excluded devices. New registrations are included unless
excluded. Enrollment, storage, and sending happen outside this resolver.

`PreferenceStore.saveChoice(notifiable, notificationType, scopeKey, channel,
choice)` saves `on` or `off`; `inherit` removes that recipient's exact choice.
`choices(notifiable, notificationType, scopeKeys)` returns scopes in the order
you supplied, including empty choices for inherited scopes.
`configuration(notifiable, notificationType, defaults, scopeKeys)` returns both
the scopes and the resolved values. Check that the caller can use the requested
notification types and scopes before calling these methods. A scope string
isn't an authorization check. `deleteRecipient(notifiable)` removes only that
recipient's choices.

`PreferenceStore.pruneChoices(constraints, limit=100)` removes a batch of stale
choices across recipients. Supply a backend QueryBuilder callback that selects
obsolete scopes and keeps live scopes and account defaults. Megaphone doesn't
know which application resources still exist. Candidates use a deterministic
composite-key order and are checked again under row locks before deletion.
`limit` must be an integer from 1 to 1,000. Keep this as a maintenance operation;
don't let a user supply an arbitrary query or scope deletion.

## Push registrations

Apply the subscriptions and device-exclusions migrations before using
`SubscriptionStore@megaphone`. `register(notifiable, endpointHash, sealedData,
label, existingId, expiresDate)` takes a SHA-256 endpoint hash and encrypted
subscription data. Pass `existingId` when renewing that recipient's registration
to preserve its device exclusions. When a subscription moves to another account,
the old registration is retired, its encrypted data is cleared, and the new
account gets a separate registration ID.

`registrations(notifiable, activeOnly=true, clock=now())` returns device metadata
without endpoints, hashes, or encrypted keys. Use
`activeRegistration(notifiable, id, clock)` internally when sending to an active,
unexpired registration. Keep that result out of client responses and logs.
`rename` and `disconnect` return false for a missing ID or another recipient's ID.
Use `setExcluded(notifiable, notificationType, deviceId, excluded)` and
`excludedIds(notifiable, notificationType)` for per-type device exclusions.
`pruneInactive(beforeDate, limit=100)` removes retired registrations and their
exclusions in batches. `deleteRecipient` removes that recipient's records.

Disconnect registrations when the user logs out or switches accounts. You'll
need to wire this into your app; Megaphone doesn't listen to authentication
events automatically.

The active list excludes expired subscriptions using the same clock as dispatch.
Pass `activeOnly=false` to show expired and disconnected registrations on a
device-management screen. A stored active flag doesn't override an expiry date.

`SubscriptionCipher(activeKeyId, keys)` encrypts JSON subscription data with
AES-256-GCM. Each key is a base64-encoded 32-byte storage key. Pass the same
nonempty recipient-and-origin context to `seal(subscription, context)` and
`unseal(sealedData, context)`. Keep old key IDs while records still use them;
new writes use the active key. These storage keys are separate from your VAPID
keys. Validate the browser's subscription fields in your enrollment endpoint.

`WebPushResponsePolicy.classify(statusCode, retryAfter="", clock=now())` returns
a delivery outcome, a safe reason code, and `retireSubscription`. A 201 or 202
means the push service accepted the request; it doesn't tell you whether the
user received it. A 404 or 410 retires the registration. A 429 or server error
can be retried with a bounded retry date. Timeouts, redirects, and unexpected
success codes leave acceptance ambiguous. Response bodies and endpoint URLs
aren't retained.

Use the classifier when you have a completed HTTP response. If transport throws
after sending, keep that result ambiguous through `DeliveryDispatcher`.

## Optional Java Web Push transport

`WebPushTransport` uses Java 11+ and the optional
[zerodep-web-push-java SDK](https://github.com/st-user/zerodep-web-push-java).
Run this from the installed module directory:

```sh
box task run taskFile=tasks/InstallWebPushSDK.cfc
```

The task downloads version 2.1.5 from Maven Central and checks SHA-256
`1337acba24004f2a702275b676eb3862e402c8775d3031b26464f0b18d3ba989`
before saving the JAR under `resources/java/webpush`. If the file already exists,
it checks that file. Add this step to your deployment build if you use push;
the regular Megaphone install doesn't download the SDK.

Load that directory with your application's Java loader. Pass its `create`
class factory, the SDK's VAPID key pair, a contact subject (`mailto:` or HTTPS),
and the push-service DNS hosts you trust to `new WebPushTransport(...)`.
Host entries can be exact names or `*.example.com` patterns. The wildcard matches
subdomains, not the parent domain. Configure these hosts in your app; don't take
the list from browser input.

The default client disables redirects and sets connect and request timeouts.
You can pass an `httpClient` to use your own transport or a test fixture. It must
keep those timeout and redirect rules and must not retry automatically.

`prepare(subscription, payload, ttlSeconds=3600)` validates the HTTPS endpoint,
keys, and single-record UTF-8 payload size, then signs with VAPID and encrypts
with `aes128gcm`. It doesn't make a network request. TTL can be zero through seven
days. Prepare the request in your eligibility callback, before marking transport
as started, and recheck registration ownership and notification access there.
Keep the prepared request internal; its URI and headers contain private data.

After the dispatcher marks transport as started, `sendPrepared(request)` sends
once and discards the response body. It returns a `WebPushResponsePolicy` outcome,
or ambiguous acceptance if transport fails. When `retireSubscription=true`,
retire that recipient's registration. One failed or expired device shouldn't
cancel another device's delivery. Sending push doesn't create inbox entries or
change preferences.

After installing the SDK, you can run
`tests.specs.integration.WebPushPreparationSpec` to check SDK request preparation
and transport fixtures. It doesn't send to real devices. Test your actual push
providers, service worker, enrollment flow, and devices separately.

## Event identities

Apply the `megaphone_events` migration to use `EventStore@megaphone`.
`record(namespace, eventKey, version, type, payload, payloadHash, createdDate)`
stores an immutable payload snapshot. Repeating the call returns the existing
event. Supply a stable hash of your canonical domain payload. Reusing the identity
with a different type or hash throws `Megaphone.Events.IdentityConflict`.
A unique database constraint handles concurrent calls.

Record events in the same datasource and transaction as your domain change.
`record` doesn't start its own transaction or call a provider. You can configure
storage with constructor `properties.table` and `properties.queryOptions`.

Event identities are separate from inbox entries. Pruning someone's inbox won't
make an old event new again. `find(id)` returns the snapshot or null. Keep event
identities for your supported replay window. Check access before showing their
content; the event store isn't a user inbox. Recording an event doesn't queue or
send deliveries.

## Durable delivery

Existing synchronous consumers can keep using their current APIs. To use durable
delivery, apply the delivery and attempt migrations.
`DurableNotificationService@megaphone.publish(event, intents, queueAdapter)`
records an event and its recipient/channel/device work in one transaction.
Each intent supplies `recipientType`, `recipientId`, `channel`, optional
`deviceId`, explicit `enabled`, `routingData`, `routingHash`, and optional
`availableDate`. Disabled channels are saved as suppressed. Enabling one later
doesn't revive old work. Publishing the same event again returns the existing
work without adding recipients or channels that became eligible afterward.

Your optional queue adapter implements `enqueue(delivery)`. Save a job reference
in the same datasource and transaction, without sending to a provider. A queue
insertion failure rolls back publication, even if the caller catches it inside
the domain transaction. Without an adapter, use `DeliveryStore.due(limit, clock)`
from a scheduler. Duplicate jobs are safe because only the current claim token
can start transport.

`due(limit=100, clock=now(), constraints)` takes an optional backend query callback
before ordering and limiting the batch. Use it to exclude deliveries that already
have live queue jobs so they don't crowd out missing jobs. Keep queue-specific
queries in your adapter and recheck under its concurrency guard before enqueueing.
Selecting candidates alone doesn't prevent two schedulers from acting on them.

`DeliveryStore@megaphone` provides `enqueue`, `find`, `forEvent`, `claim`,
`startTransport`, `complete`, `due`, `attempts`, and `recoverExpired`.
Constructor properties let you set `table`, `attemptsTable`, `eventsTable`, and
`queryOptions`. Use the domain transaction's datasource for events, deliveries,
and queue jobs. Queue delivery IDs rather than serialized users or credentials.

`DeliveryDispatcher@megaphone.dispatch(id, eligibility, sender, leaseSeconds=60,
maxAttempts=5, retrySeconds=30)` claims work and calls your callbacks:

- `eligibility(delivery)` prepares content and checks current access, preferences,
  registration ownership, feature availability, and source revision just before
  transport. Return `status` as `ready`, `suppressed`, `deferred`, or `permanent`,
  with optional safe reason, retry date, and prepared content. You supply the
  application's authorization rules.
- `sender(delivery, prepared)` sends through your channel adapter. Return `outcome`
  as `accepted`, `retryable`, `permanent`, or `ambiguous`, with optional provider
  reference, safe reason, and retry date. Use `retryable` only when you know the
  provider rejected the request before acceptance. An uncertain timeout is
  `ambiguous`.

The transport-start marker must succeed before sending. If a lease expires before
that point, a new worker can retry and the old token can no longer start transport.
If it expires or throws afterward, acceptance is ambiguous and automatic resends
stop. A late result from that same lease can still record acceptance. Establish a
definite outcome before retrying. Provider acceptance doesn't mean the recipient
received or read the message.

Feature pauses and preparation failures before transport don't use up the actual
send allowance. `attemptCount` counts claims; `transportCount` counts starts.
`recoverExpired(limit=100, clock)` checks expired processing rows in batches.
Run it alongside your due-work scheduler so lost jobs don't leave work stranded.
Claim and policy state is committed before calling the provider. Don't wrap
network I/O in a new domain transaction in your sender callback.

`reconcileAccepted(id, acceptance, clock=now())` settles work using a verified
receipt, including late acceptance or an import from the previous delivery owner.
The callback receives the immutable delivery and returns `{ accepted: false }`
or `{ accepted: true, providerReference: "receipt-id" }`. Verify that the receipt
belongs to that delivery. Keep the callback local, without external I/O.
Confirmed acceptance prevents queued or running work from sending again.
Existing attempt outcomes stay attached to their original attempts. Authorize
this operation in your app before exposing it through an endpoint.

`pruneAttempts(beforeDate, limit=200)` removes diagnostics for terminal deliveries
and keeps the provider reference. `pruneResolvedEvents(eventsBefore,
deliveriesBefore, limit=100)` removes event identities and their work only after
the replay window, when every delivery is terminal and old enough. Pending or
ambiguous work keeps its evidence. Reject old events outside your replay window
before publishing; use `importNotification` when you only need to import history.
Neither cleanup method removes inbox entries or domain audit history.

Set your cutoffs in scheduled configuration. For example, you might keep terminal
attempt diagnostics for 90 days and resolved event identities for 365 days.
The event cutoff must be beyond your supported replay window. The inbox count
cap is a separate setting.

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

`DatabaseNotificationService.getNotificationSlice()` returns
`{ results, nextCursor, hasMore }`. Pass `nextCursor` as `afterCursor` to get the
next page. Results are ordered by newest `createdDate`, then descending ID.
New entries ahead of that position won't repeat items, and deleting the boundary
row won't break the next page.

The cursor belongs to a recipient, but you'll still need to check access.
Recipient ownership, visibility constraints, archive mode, and unread filters
apply on every page. Reset the cursor when filters change. Start a fresh first
page to include new arrivals.

Configure the database provider's `cursorTimestampExpression` to return timestamp
text as `yyyy-MM-dd HH:mm:ss[.fraction]` without losing database precision.
Set `cursorTimestampSqlType` to the JDBC binding type your adapter needs.
For PostgreSQL, use `cursorTimestampExpression = 'CAST("createdDate" AS TEXT)'`
and `cursorTimestampSqlType = "other"`. UUID IDs also need `idSqlType = "other"`.
Keep these expressions in application configuration, never caller input.
The existing offset pagination methods don't need these settings.

An invalid cursor or one from another recipient throws
`Megaphone.Database.InvalidCursor`. Set `cursorIdentifierPattern` for constrained
IDs, such as UUID columns, to reject malformed IDs before JDBC conversion.
You can keep previous cursor positions for back navigation, but each request
checks access again. A cursor keeps your place; it doesn't freeze permissions,
read state, or archive state. Pruned entries disappear without shifting a numeric
offset. Inbox pagination and retention leave pending deliveries and event
identities alone.
