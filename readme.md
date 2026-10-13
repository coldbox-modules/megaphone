# Megaphone

## A protocol-based library for sending Notifications in ColdBox

## Requirements

Megaphone requires JDK 11 or newer, ColdBox 6+, and Adobe ColdFusion 2021+ or Lucee 5+. Use a Java version supported by your engine when it needs a newer JDK. CI selects Java per engine: 11 for Lucee 5/6 and Adobe 2021, 17 for Adobe 2023, and 21 for BoxLang and the scheduled bleeding-edge engines. BoxLang runs in both native and CFML compatibility modes with ColdBox 8; the scheduled matrix also covers both modes on bleeding-edge BoxLang and ColdBox.

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
						"table": "megaphone_notifications",
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
            channelName = "database" // default is "database",
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
            channelName = "database" // default is "database",
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

## Durable notifications

Use the same notifiable and notification conventions for immediate and queued delivery:

```cfc
megaphone.notify(user, "OrderReadyNotification", { "orderId": orderId });
var publication = megaphone.queue(
    notifiables = user,
    notification = "OrderReadyNotification",
    properties = { "orderId": orderId },
    options = { "namespace": "Orders", "eventKey": orderId, "version": 1 }
);
publication.getEvent().getId();
publication.getDeliveries()[1].getId();
```

`NotificationService.plan()` accepts the same arguments and returns a `NotificationPlan` without writing or sending. `queue()` plans and stores work in the caller's datasource transaction. `SendsNotifications` also provides `queue()`.

Options are `namespace` (default `megaphone`), `eventKey` (generated if omitted), `version` (1), `occurredAt` and `availableDate` (now), and optional `admitAfter`. Occurrences older than the cutoff return an expired publication without recording work. Equality is admitted.

Persist `plan.getMemento()` when admission must precede worker handoff. Restore it using a `NotificationPlan@megaphone` method provider followed by `.populateFromMemento(saved)` and call `queuePlan(plan)`. Its version 1 memento contains `event`, `deliveries`, and optional `admitAfter` and `queueOptions`. The latter retains explicit `connection` and `queue` choices for handoff. It preserves identities, payloads, hashes, destinations, and channel choices. A trusted producer may use `queuePlan(plan, alreadyAdmitted=true)` after validating its original persisted admission. This bypasses the replay cutoff; it does not replan the audience.

Notifications extend `BaseNotification`, implement `via(notifiable)` and the usual `to{Provider}` methods, and may override `getChannelPreferences(notifiable)` to return a channel-name map of `{ enabled, source }`. The default enables the channels returned by `via()`. Synchronous delivery skips disabled channels. Durable delivery records them as suppressed; later opt-in does not revive them.

`getQueueProperties()` defaults to the explicitly populated properties. Notifications configured through setters must override it to return their durable properties. Store JSON data rather than components, closures, credentials, users, or prepared mail/request objects. `getNotificationMapping()` defaults to the WireBox identity, or the component path for directly constructed instances; override it when notification type and reconstruction mapping differ. `getDeliveryContext(notifiable, channelName)` provides application routing context, separate from the notification properties.

### Module configuration

```cfc
moduleSettings.megaphone = {
    "channels": {
        "database": { "provider": "DatabaseProvider@megaphone", "properties": {} },
        "email": { "provider": "EmailProvider@megaphone", "properties": { "durableAdapter": "ActivityMailAdapter" } },
        "push": { "provider": "WebPushProvider@megaphone", "properties": { "runtime": "ApplicationPushRuntime" } }
    },
    "storage": {
        "events": {}, "deliveries": {}, "preferences": {}, "subscriptions": {}
    },
    "queue": {
        "queueAdapter": "CBQNotificationQueue@megaphone",
        "defaultConnection": "", "defaultQueue": "",
        "notifiableResolver": "NotifiableResolver",
        "eligibilityPolicy": "NotificationEligibility",
        "snapshotHasher": "NotificationSnapshotHasher@megaphone",
        "leaseSeconds": 60, "maxAttempts": 5, "retrySeconds": 30,
        "maxRecoveryAttempts": 5, "maxRecoveryAllowance": 45
    }
};
```

Storage settings accept `table`, `queryOptions`, and `datasource`. Deliveries also accept `attemptsTable`, `eventsTable`, and `recoveriesTable`; subscriptions accept `exclusionsTable`. Adapt migrations when using custom table names, and keep related table settings consistent. New public APIs use `notifiableType`, `notifiableId`, and `channelName`; existing storage columns remain unchanged.

Megaphone includes the `CBQNotificationQueue@megaphone` adapter, but does not install cbq. Install and configure cbq in your application to use this default adapter. It dispatches a `NotificationDeliveryJob@megaphone` containing only the delivery ID, using cbq's registered default connection and that connection's default queue. cbq uses the Provider configured on that connection. Set `queue.defaultConnection` and `queue.defaultQueue` to choose the default route. Pass `connection` and `queue` to `plan()`, `queue()`, or `queuePlan()` to choose a route for a particular call. cbq supplies the queue and worker defaults. The job starts with one cbq attempt. After a known retryable, deferred, or busy outcome, Megaphone allows one more attempt and releases the job through cbq with the saved availability or lease delay. The registered Provider handles backoff; unhandled errors receive no automatic extra attempt. Ambiguous acceptance never triggers another send.

Register your connections and worker pools through your application's cbq config. Megaphone keeps those registrations and does not select or create a queue Provider. Empty `queue.defaultConnection` and `queue.defaultQueue` settings use cbq's default connection and the selected connection's default queue. Per-call `connection` and `queue` arguments take precedence over these settings. Applications that only use synchronous notifications can start without cbq. Calling the cbq adapter without an available, active cbq module throws `Megaphone.Queue.MissingCBQ`; failed queue insertion rolls back the event and deliveries. Custom adapters and polling do not require cbq.

Follow your queue Provider's setup instructions. A database queue on the same datasource can join the publication transaction. External queues cannot roll back published jobs with database writes, so arrange the commit handoff before workers consume delivery IDs. A synchronous Provider executes the job inline. An enqueue failure rolls back Megaphone's event and deliveries, subject to the selected Provider's external effects.

You can still provide a custom `queue.queueAdapter` implementing `enqueue(delivery, connection, queue)`. The optional connection and queue arguments are forwarded when supplied by the caller. It should queue only the delivery ID and preserve the selected queue's transaction and handoff semantics. Explicitly set the adapter to an empty string if a scheduled worker polls `getDueDeliveries()` and `recoverExpired()` instead.

A notifiable resolver implements `resolve(type, id)` and returns the matching current notifiable or null. An optional `deliveryPolicy` mapping implements `getDispatchOptions(id)` to provide lease, attempt, and retry options; explicit dispatch options take precedence.

An optional eligibility policy implements `check(delivery, notifiable, event)` and returns a `DeliveryPreparation` with status `ready`, `suppressed`, `deferred`, or `permanent`, plus optional reason and retry date. Application authorization, source revision, and feature checks belong here. Preferences are checked before transport too.

The default snapshot hasher sorts object keys and preserves array order. An application hasher implements `digest(value, context)`, where context includes `namespace` and `kind` (`payload` or `routing`). Retain an existing canonical hash algorithm when upgrading persisted events.

### Providers and dispatch

Providers may implement the optional `IDurableNotificationProvider` capability:

- `prepareDelivery(notifiable, notification, delivery)` returns a `DeliveryPreparation`; prepare content without provider I/O.
- `sendDelivery(prepared, delivery)` returns a `DeliveryResult` with status `accepted`, `retryable`, `permanent`, or `ambiguous` and optional reason, provider reference, and retry date.

Use `prepared.getData()` for transient transport objects. Its memento contains status metadata, not transport data. Existing synchronous `notify()` still returns a `BaseNotification`. A provider lacking durable support is rejected during planning. Durable email requires a configured adapter that supplies explicit acceptance evidence.

`NotificationDeliveryService.dispatch(id, options={})` resolves the saved notification and registered channel, checks current eligibility, prepares delivery, checks again, and records transport start before sending. It returns a `DeliveryResult`. Options can override lease, attempt, and retry settings.

Duplicate jobs cannot share a lease. Preparation failures and feature pauses do not consume transport allowance. An exception after transport starts is ambiguous and cannot trigger an automatic resend. Acceptance does not establish receipt or read state. Do not wrap provider I/O in an application transaction.

## Preferences and Web Push

`NotificationPreferenceService@megaphone` provides `getPreferences`, `setPreference`, `resolvePreferences`, `importPreference`, `prunePreferences`, and `deleteNotifiable`. Supply a notifiable, notification type, and application-defined scopes. `setPreference(notifiable, notificationType, scopeKey, channelName, choice)` stores `on` or `off`; `inherit` removes the exact override. `resolvePreferences(notifiable, notificationType, defaults, scopeKeys)` applies scopes from broadest to most specific and returns both explicit scopes and effective values. Authorize scope access in the application.

`WebPushProvider` participates in `via()` using its configured channel name. Notifications implement `toWebPush(notifiable, delivery)`; `routeNotificationForWebPush()` on a notifiable may provide device metadata, otherwise owned active registrations are used. Device exclusions apply per notification type. No eligible destination produces suppressed work without a phantom send. One expired device does not cancel another.

`PushSubscriptionService@megaphone.register(notifiable, subscription, label, existingId="", expiresDate, channelName="push")` validates and encrypts browser subscriptions internally. Its public registration metadata excludes endpoints, hashes, and encrypted keys. Use `getRegistrations`, `rename`, `disconnect`, `setExcluded`, `getExcludedIds`, `pruneInactive`, and `deleteNotifiable` for device lifecycle. `retireExpired(notifiable, clock, limit)` retires expired destinations independently; omit the notifiable for bounded maintenance across owners. `getActiveRegistration` is for trusted delivery infrastructure and must not be exposed to clients.

Push channel properties may configure `enabled`, `origin`, `publicKey`, `privateKey`, `subject`, `allowedHosts`, `activeStorageKeyId`, and `storageKeys` directly. The bundled runtime accepts base64 PKCS8/X509 VAPID keys and a storage keyring of base64 AES-256 keys. An optional runtime mapping implements `enabled`, `context(notifiable)`, `cipher`, and `transport`; use it to retain existing recipient/origin encryption contexts. Infrastructure is resolved lazily so disabled or incomplete push does not prevent other channels from starting.

Megaphone declares the Web Push SDK as a pinned JAR dependency in `box.json`; CommandBox installs it with the module. The bundled transport requires Java 11+; there is no separate SDK installation step.

The runtime verifies the pinned SDK checksum before loading. Enrollment and service-worker integration remain application responsibilities. Registration does not change preferences or publish activity. Disconnect devices on logout/account switch. Provider tests use fixture HTTP clients; verify real devices separately before deployment.

## Inbox cursors and read state

`DatabaseNotificationService.getNotificationsAfter(notifiable, channelName="database", afterCursor="", maxRows=25, constraints, archiveMode="active", unread=false)` returns `DatabaseNotificationKeysetCursor`. The delegate offers the same method with an implicit notifiable. Use `getResults()`, `getNextCursor()`, `hasNext()`, and `next()`; its memento is `{ results, nextCursor, hasMore }`.

Use `getNotifications()` for numbered pages, backward navigation, and pagination totals. `getNotificationsAfter()` adds forward-only pagination for a changing feed; it does not replace the numbered-page methods. Numbered pages default to all archive states, while the forward cursor defaults to active entries. Keyset pagination orders by exact stored creation time and ID, handles deleted boundaries and concurrent arrivals, and binds tokens to the notifiable. Configure `cursorTimestampExpression`, `cursorTimestampSqlType`, and `idSqlType` for the existing database adapter. PostgreSQL UUID columns use `other`; timestamp text must preserve precision. These settings are backend configuration, never client input.

Apply the inbox-state migration and enable `properties.inboxState=true` for archive/group queries. Constraints run inside ownership filters before pagination and remain on loaded handles for mutations. `configureQuery(callback, constrainMutations=false)` is only for display filters; leave authorization constraints enabled. Reset the cursor when filters change.

Released `markAsRead(readDate)` and cursor `markAllAsRead(readDate)` replace the timestamp. Use `markAsReadIfUnread()` and `markAllAsReadIfUnread()` to preserve the first read time. Read snapshots update only captured, currently authorized IDs; later arrivals remain unread. Archive and unarchive leave read state alone.

`importNotification()` retains stable history IDs and sends nothing. `pruneNotifications()` removes bounded batches above the configured inbox cap. Inbox retention is separate from event replay and delivery evidence retention.

## Delivery history, recovery, and upgrade

`NotificationDeliveryService` provides `getEvent`, `getDelivery`, `getDeliveriesForEvent`, `getDeliveries`, `getStateCounts`, `getAttempts`, and `getRecoveryHistory`. Delivery pages return objects with `getResults()`, `getHasMore()`, and `getMemento()`. Events, deliveries, attempts, and recovery receipts expose accessors and mementos. Recovery history is a `NotificationRecoveryPage`; its memento retains the familiar results/hasMore fields. Delivery `getAttributes()` exposes application-selected display columns without mixing them into delivery identity. Authorize operator access before listing data.

Use `getRecoveryVersion(delivery)` for an optimistic command token. `requestRecovery(id, requestKey, actorId, expectedVersion, eligibility, queueAdapter, additionalAttempts=1, actorLabel="")` checks a live eligibility callback returning `DeliveryPreparation`, records an immutable receipt, and enqueues atomically. It returns `DeliveryRecoveryResult`. Only retryable/permanent work can recover; accepted, ambiguous, suppressed, and processing work cannot. Replay returns the same receipt without another job. Limits default to five transports per request and 45 additional transports over the lifetime; configure them through `queue`.

`reconcileAccepted(id, acceptance)` accepts a locally validated `{ accepted, providerReference }` receipt, including authoritative late or imported evidence. It does not resend or rewrite older attempt diagnostics. Maintenance methods include `recoverExpired`, `pruneAttempts`, and `pruneResolvedEvents`. A `beforePrune(event, deliveries)` callback receives objects after owner locks and terminal-state checks, in the same transaction, for preserving application retirement evidence. No external I/O belongs in that callback.

Apply `2026_10_12_180000_add_megaphone_notification_mapping.cfc` after the existing migrations. Backfill reconstruction mappings for existing events without changing payloads, hashes, delivery IDs, or queue references. Application readers of saved RC admissions must translate their old field names into the version 1 plan shape without resolving a new audience or preferences.

The unreleased `DurableNotificationService`, `DeliveryDispatcher`, and struct-returning `getNotificationSlice()` API have been replaced. Stores remain persistence implementation details; consumers use the services above. Merging, package publication, consumer installation, and deployment are separate verification steps.

## Model layout

The core notification service, base notification, and inbox models live at the root of `models`. Related classes are grouped by their role:

| Folder | Contents |
| --- | --- |
| `Delivery` | Plans, events, publications, delivery operations, results, and recovery history |
| `Queue` | The cbq adapter and delivery job |
| `Storage` | Event, delivery, preference, and subscription stores |
| `Preferences` | Preference resolution and the preference service |
| `WebPush` | Subscription registration, encryption, SDK loading, and HTTP transport |
| `Providers`, `Delegates`, `Interfaces` | Notification channels, notifiable delegates, and extension contracts |

WireBox names such as `NotificationPlan@megaphone` and `WebPushRuntime@megaphone` stay the same. Prefer those mappings when creating or overriding module objects.
