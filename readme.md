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

### Browsing delivery history

`DeliveryStore.getPage(maxRows=50, offset=0, constraints=callback)` returns
`{ results, hasMore }` without claiming or sending work. Results are ordered by
updated date descending, then delivery ID. Page sizes are limited to 1–200, with
one extra row fetched to check for another page. Routing data is decoded for you.

The callback receives a query with the `delivery` alias before ordering and
pagination. Use it to add filters, domain joins, and metadata. Check operator
access and add the recipient, namespace, and domain restrictions your app needs.
This method doesn't expose an HTTP endpoint or choose your application's scopes.

### Recovering failed deliveries

`DeliveryStore.requestRecovery(id, requestKey, actorId, expectedVersion,
eligibility, queueAdapter, additionalAttempts=1, actorLabel="")` records who
requested a retry and queues the work in the same transaction. Get
`expectedVersion` from `recoveryVersion(delivery)` and check that the operator
can recover this delivery before calling it.

Your eligibility callback checks current recipient access, preferences, and
domain state, then returns `{ status: "ready" }`. The queue adapter saves its job
in the same datasource transaction. It must not send to a provider there.

You can recover retryable or permanently failed work. Accepted, ambiguous,
suppressed, and processing work can't be recovered. Existing attempt and transport
counts, provider references, and future backoff are preserved. Each request adds
1–5 transports, up to 45 additional transports over the delivery's lifetime.

Repeating the same request key and intent returns the original receipt. Reusing
that key for different intent is a conflict. A stale version or failed eligibility
check creates no receipt or job. Check for external acceptance before requesting
recovery; a permanent state alone doesn't prove the old provider rejected it.

`recoveryHistory(id, maxRows=20, offset=0)` gives you pages of recovery receipts,
including the operator, previous state, counts, evidence, and added allowance.
Resolved-event cleanup removes these receipts with the other delivery diagnostics.
Migration 010002 completes the column addition from 010000. Rolling back 010002
leaves that column for 010000 to remove when rolling back the recovery feature.

Attempt cleanup locks the delivery and checks that it's still terminal before
removing expired diagnostics. Event cleanup locks the event and its deliveries
in ID order, then checks every delivery's terminal state and settlement cutoff.
Recovering work protects the event, attempts, and receipts from cleanup. Settling
it again starts a new retention period. Choose an event cutoff beyond your
supported replay window; the inbox retention setting doesn't define that window.

### Counting delivery states

`DeliveryStore@megaphone.stateCounts(constraints)` returns channel/state/total
groups using distinct delivery IDs. The optional callback gets the same `delivery`
alias as `getPage`. Use it to filter by ownership, namespace, or migration before
counting. You can compare stored states without loading every delivery or writing
queries against Megaphone's tables. These counts tell you the current delivery
state, not whether the recipient received or read the message.

### Limiting event replay

`DurableNotificationService.publish(event, intents, queueAdapter, admitAfter)`
lets you set an occurrence cutoff. Supply the saved domain occurrence time in
`event.createdDate`. A missing or invalid value throws
`Megaphone.Events.OccurrenceRequired`. An occurrence strictly older than the
cutoff returns `{ event: { id: "", created: false, expired: true }, deliveries: [] }`
without saving an event, delivery, or queue job. An occurrence equal to the cutoff
is allowed. Calls without `admitAfter` keep their existing behavior.

You can call `canPublish(occurredAt, admitAfter)` before resolving recipients and
preferences to skip that work for expired events. `publish` checks again before
saving. An expired publication doesn't cancel existing deliveries; their owner
still handles recovery. Imports that don't send and migrations of pending work
can use their own cutoff rules.

Choose an event retention cutoff no later than the admission cutoff, and keep
unresolved work independently. Use the original saved occurrence time on every
producer, not the time a retry runs. If you've pruned event identities, restore
the deduplication evidence before widening the replay window. Admission checks
don't run cleanup or remove queue and provider records for you.

`pruneResolvedEvents(eventsBefore, deliveriesBefore, limit=100, constraints)`
accepts a backend query callback. It filters candidates before the batch limit
and runs again against the locked event before deletion. Use it to limit cleanup
to your namespace or keep events with external queue or import references.
Megaphone still checks terminal states, settlement cutoffs, and parent/child
locks. Your external reference updates need compatible locking so they don't
race event deletion.

`DeliveryStore.find(id, lockRow=false)` can lock a delivery for lifecycle work in
your app. Set `lockRow=true` inside your transaction and keep that transaction
open until the external reference update is finished. Recovery, claims,
completion, and retention use the same delivery lock. The lookup doesn't start
a transaction or check caller authorization for you.

You can also pass `beforePrune(event, deliveries)` to `pruneResolvedEvents`.
It runs inside the cleanup transaction after the event and terminal deliveries
are locked and checked, but before they're removed. The callback gets copies of
the stored rows. Use it to save a small retirement receipt in the same datasource.
If it throws, deletion rolls back. Keep external I/O out of the callback. Pending,
ambiguous, or otherwise ineligible events never reach it. Your app still manages
its references and any evidence it keeps.

### Building a local package

Run `box task run taskFile=tasks/PrepareLocalArtifact.cfc` from the module root
to build a local archive with ForgeBox's package filtering. It checks required
runtime and migration files, excluded development files, dependencies and SDK
JARs, duplicate paths, and each packaged file's source hash.

The task writes `.tmp/megaphone-local-artifact.zip` and a receipt with file sizes
and SHA-256 hashes. It doesn't publish or change the version. You'll still need
to check clean installation, released-version adoption, and runtime compatibility
separately.
