# Megaphone

## A protocol-based library for sending Notifications in ColdBox

## Documentation
Installation: `box install megaphone`

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

## Providers

### DatabaseProvider
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

### EmailProvider

#### Dependencies
The `EmailProvider` requires `cbmailservices` to be installed.

#### Usage
To send via the `EmailProvider`, add a `toEmail` method to your notification:

```cfc
public Mail function toEmail( notifiable, newMail ) {
    return newMail(
        from: "noreply@example.com",
        subject: "Megaphone Email Notification",
        type: "html",
        bodyTokens: { product: "ColdBox" }
    ).setBody( "
        <p>Thank you for downloading @product@, have a great day!</p>
    " )
}
```

In addition to the notifiable instance in the parameters, you will receive a `newMail` function that will give you a `Mail` instance from `cbmailservices`.

You must return a `Mail` instance from the method.  You do not need to call `send` yourself. `megaphone` will handle sending the email.

The email recipient can be set in two ways.  First, you can explicitly set the `to` in the `toEmail` method:

```cfc
public Mail function toEmail( notifiable, newMail ) {
	return newMail(
		to: notifiable.getEmail(),
		from: "noreply@example.com",
		subject: "Megaphone Email Notification",
		type: "html",
		bodyTokens: { product: "ColdBox" }
	).setBody( "
		<p>Thank you for downloading @product@, have a great day!</p>
	" )
}
```

Second, you can let your `notifiable` instance define where to send the email.  You do this by implementing a new method on your notifiable instance: `routeNotificationForEmail`.

```cfc
component name="User" accessors="true" {

    property name="id";
    property name="email";

    public string function getNotifiableId() {
        return getId();
    }

    public string function getNotifiableType() {
        return "User";
    }

    public string function routeNotificationForEmail() {
        return getEmail();
    }

}
```

Any time you want `megaphone` to set the recipient implicitly, all your notifiables receiving the email need to implement the `routeNotificationForEmail` method.
If you do not send emails to a notifiable type or you always explicity set the recipient, you may omit this method.

#### Configuration
An `EmailProvider` can be configured with three properties:
```cfc
moduleSettings = {
    "megaphone": {
        "channels": {
            "email": {
                "provider": "EmailProvider@megaphone",
                "properties": {
                    "mailer": "default",
                    "onSuccess": () => {},
                    "onError": () => {}
                }
            }
        }
    }
}
```

The `mailer` property is the default mailer for this channel. (It does not have to be the `default` mailer in cbMailservices.) If you set the mailer when calling `newMail` in your notification, your custom mailer will override the channel default.

The `onSuccess` and `onError` callbacks are the default callbacks called on the `Mail` object after is has been sent.  By default, these are both no-ops.
### Delivery backend pagination

`DeliveryStore.getPage(maxRows=50, offset=0, constraints=callback)` returns
`{ results, hasMore }` without claiming work or invoking providers. It orders by
updated date descending and delivery ID, clamps the page size to 1–200, and
uses a one-row lookahead. The callback receives a query using the stable
`delivery` alias and runs before ordering and pagination; it can add authorized
filters, domain joins and selected metadata. Returned routing data is decoded.
This is a trusted backend API: consumers must enforce their operator policy and
supply the recipient, namespace and domain restrictions their application needs.
It does not expose an HTTP endpoint or assume application scope names.

### Audited operator recovery

`DeliveryStore.requestRecovery(id, requestKey, actorId, expectedVersion,
eligibility, queueAdapter, additionalAttempts=1, actorLabel="")` records a recovery
receipt and queues work in the same transaction. Obtain the version from
`recoveryVersion(delivery)`; authorize the operator and delivery in application code.
The eligibility callback must return `{ status: "ready" }` after checking current
recipient access, preferences and domain state. The queue adapter must participate
in the same datasource transaction and must not perform external transport.

Only retryable or permanently failed work can recover. Accepted, ambiguous,
suppressed and processing work cannot. Recovery preserves cumulative attempt and
transport counts, provider references and future backoff. Each command grants
1–5 additional transports, with a lifetime limit of 45 additional transports per
delivery. A repeated request key with identical intent returns its original
receipt; different intent conflicts. Stale versions and failed eligibility do not
create a receipt or queue work. Reconcile external acceptance before requesting
recovery; a permanent state alone is not proof that a legacy provider rejected it.

`recoveryHistory(id, maxRows=20, offset=0)` provides bounded receipt pages with
operator identity, prior state/counts/evidence and granted allowance. Resolved-event
retention removes these receipts along with their delivery diagnostics. Migration
010002 completes the column addition intended by 010000; its down retains the
column for 010000's removal when rolling back the recovery feature.

Attempt cleanup locks the delivery owner and rechecks that it remains terminal
before deleting expired diagnostics. Resolved-event cleanup locks the parent event
and its deliveries in ID order, then rechecks every delivery's terminal state and
settlement cutoff. Reopening work for recovery protects the event, attempts and
recovery receipts; settling it again starts a new settlement retention period.
Consumers must choose an event cutoff beyond their supported replay window before
invoking resolved-event cleanup. Inbox retention alone does not define that window.

### Delivery reconciliation counts

`DeliveryStore@megaphone.stateCounts(constraints)` returns channel/state/total groups using distinct delivery IDs. The optional trusted backend callback receives the same `delivery` alias as `getPage` and applies application ownership, namespace or migration constraints before aggregation. It supports reconciliation without loading every delivery or coupling applications to module storage queries. These are current durable states, not evidence that a provider delivered or a recipient read a message.

### Bounded event replay admission

`DurableNotificationService.publish(event, intents, queueAdapter, admitAfter)` accepts an optional occurrence cutoff. When supplied, `event.createdDate` must be the persisted domain occurrence time; missing or invalid values raise `Megaphone.Events.OccurrenceRequired`. Occurrences strictly older than the cutoff return `{ event: { id: "", created: false, expired: true }, deliveries: [] }` before any event, delivery, or queue writes. Equality remains admitted. Calls without this option retain their existing behavior.

`canPublish(occurredAt, admitAfter)` exposes the same check for consumers that want to avoid recipient/preference planning for retired events. `publish` repeats the check at its persistence boundary. Expired publication does not delete or cancel existing deliveries; their recovery continues through the delivery owner. Explicit no-send imports and pending-work migration can use their own admission contract.

Choose an event retention cutoff no later than the admission cutoff and retain unresolved work independently. Use immutable domain timestamps on every producer, never a retry's processing time. Do not widen the accepted replay interval after pruning its identities without restoring deduplication evidence. An admission check alone does not enable cleanup or bound unrelated queue/provider bookkeeping.

`pruneResolvedEvents(eventsBefore, deliveriesBefore, limit=100, constraints)` also accepts an optional trusted backend query constraint. It filters candidates before the batch limit and is reapplied to the locked parent lookup before deletion. Consumers can constrain their namespace and preserve events with external queue/import references without putting application tables into Megaphone. The usual terminal-state, settlement cutoff, and parent/child locking checks still apply. External systems must use compatible ownership/locking rules; this callback is not permission to race inserts of references against deletion.

`DeliveryStore.find(id, lockRow=false)` can lock the delivery row for trusted consumer lifecycle work. Use `lockRow=true` only inside the consumer's transaction and keep the transaction open through the external-reference mutation. Recovery, claims, completion, and retention use the same owner lock; a locked lookup does not itself authorize a caller or supply a transaction.

`pruneResolvedEvents` additionally accepts `beforePrune(event, deliveries)`. This trusted backend callback runs after the parent and terminal children are locked and validated, before removal, inside the same transaction. It receives copies of the stored event and delivery rows. Consumers may persist minimal retirement receipts using the same transaction-compatible datasource; a callback exception aborts deletion. Keep external I/O out of the callback. Pending, ambiguous, or otherwise ineligible events never invoke it. Applications remain responsible for protecting their reference lifecycle and reconciling any retained evidence.

For a local unpublished archive using CommandBox's ForgeBox package filtering, run `box task run taskFile=tasks/PrepareLocalArtifact.cfc` from the module root. The task invokes the archive builder only; it never publishes or changes versions. It checks required runtime/migration files, rejects development/dependency/SDK contents and duplicate paths, compares every packaged file with its source, and records a per-file SHA-256/size manifest. It writes `.tmp/megaphone-local-artifact.zip` plus a checksum receipt. This is a source artifact check, not proof of clean installation, released-version adoption, or runtime compatibility.
