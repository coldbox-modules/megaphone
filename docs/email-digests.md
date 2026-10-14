# Email digests (1.2.0)

A named digest lets a Notifiable receive a scheduled summary or an immediate one-item email. Notifications use [EmailDigestProvider](https://megaphone.ortusbooks.com/providers/emaildigestprovider) in either case. The same policy, renderer, and receipt-aware email channel handle both timings.

Each digest has its own subscription, calendar schedule, and timezone. The application decides what the digest contains and whether each item is still eligible when the email is prepared.

### Configuring a digest

Apply `2026_10_14_120000_create_megaphone_email_digests` through your application's migration ledger. It adds `megaphone_digest_subscriptions`, `megaphone_digest_items`, `megaphone_digest_batches`, and `megaphone_digest_admissions`. Use the same transactional datasource for these tables, notification events, and deliveries.

Configure the collection channel, named definition, and storage:

```cfml
moduleSettings.megaphone = {
    "channels": {
        "email": {
            "provider": "EmailProvider@megaphone",
            "properties": { "durableAdapter": "ReceiptAwareEmailAdapter" }
        },
        "emailDigest": { "provider": "EmailDigestProvider@megaphone", "properties": {} }
    },
    "digests": {
        "productUpdates": {
            "schedule": "everyWeekOn 1 09:00",
            "timezone": "UTC",
            "emailChannel": "email",
            "policy": "ProductDigestPolicy",
            "renderer": "ProductDigestRenderer"
        }
    },
    "storage": {
        "digests": { "datasource": "applicationDatabase" },
        "events": { "datasource": "applicationDatabase" },
        "deliveries": { "datasource": "applicationDatabase" }
    },
    "queue": { "notifiableResolver": "NotifiableResolver" }
};
```

`NotifiableResolver.resolve(type, id)` loads the current Notifiable or returns null when it no longer exists. Use your existing resolver if the application already uses [Durable Delivery](https://megaphone.ortusbooks.com/notification-storage-and-delivery/durable-delivery).

The named definition provides scheduling and content behavior. The default selection includes every currently eligible item, newest occurrence first, with item-key ordering for ties. Supply `selectItems` to choose a smaller or differently ranked set. Items not selected at a cutoff are permanently discarded rather than carried into another digest. `storage.digests` accepts `datasource`, `queryOptions`, `table` for subscriptions, and `itemsTable`, `batchesTable`, and `admissionsTable` for the other tables. Custom names need matching application migrations.

### Choosing a delivery mode

Subscriptions start off. Store the user's choice using `EmailDigestService@megaphone`:

```cfml
var digests = wirebox.getInstance( "EmailDigestService@megaphone" );

digests.setSubscription(
    notifiable = user,
    digestName = "productUpdates",
    mode = "digest",
    timezone = user.getConfirmedTimezone() ?: "UTC"
);
```

Use `off`, `immediate`, or `digest`. `timezone` uses the same Java timezone identifiers and validation as ColdBox `setTimezone()`. When omitted it inherits the definition's timezone, then the module scheduler's timezone. Pass a shortcut `schedule` to override the named default for this subscription. The example explicitly falls back to UTC for an account with no confirmed timezone.

The Notification needs only one route. Megaphone reads the named subscription to choose scheduled collection, an immediate one-item batch, or suppression:

```cfml
component extends="megaphone.models.BaseNotification" accessors="true" {
    property name="digests" inject="EmailDigestService@megaphone";
    property name="productId";
    property name="updateEventId";
    property name="updateOccurredAt";

    public array function via( required any notifiable ) {
        return [ "emailDigest" ];
    }

    public struct function toEmailDigest( required any notifiable ) {
        return {
            "digestName": "productUpdates",
            "itemKey": variables.digests.itemKey( [ "product.updated", variables.updateEventId, 1 ] ),
            "occurredAt": variables.digests.occurredAt( variables.updateOccurredAt ),
            "data": { "productId": variables.productId }
        };
    }

}
```

Call `notify()`, `queue()`, or `queuePlan()` as usual. `plan()` captures the item without writing or sending. In `digest` mode, publication collects it for the next native schedule and creates no mail job yet. In `immediate` mode, publication freezes just that new item and creates a durable email delivery immediately, without waiting for a calendar cutoff. `queuePlan()` enqueues that delivery through the configured queue adapter. Synchronous `notify()` dispatches it through the same digest renderer; call synchronous sends after domain transactions commit.

The source Notification does not need `toEmail()` or a separate immediate-email route. The Notification returned by the digest renderer supplies `toEmail()` for both one-item and multi-item batches. The `email` channel remains the underlying receipt-aware transport selected by the definition's `emailChannel`.

A repeated identical subscription update keeps pending items. Changing mode, timezone, or schedule starts a new generation and suppresses obsolete collected work. Returning to Digest does not replay it. Call `setSubscription()` transactionally when the application changes that preference or confirmed timezone. Subscriptions using the named default resolve it again after application reload; explicit shortcut overrides remain independent. Treat a change to configured schedules as an application reload. Use `registerDigest()` to add a new name at runtime.

### Use one email route per product-update notification

In the catalog example, `ProductUpdatedNotification.via()` returns only `[ "emailDigest" ]`. It does not return `[ "email", "emailDigest" ]`. The named subscription chooses the timing within that one route:

| Subscription mode | Notification route | Result |
| --- | --- | --- |
| `immediate` | `[ "emailDigest" ]` | One item is rendered and delivered immediately through the digest pipeline. |
| `digest` | `[ "emailDigest" ]` | The item is collected for the next scheduled summary. |
| `off` or absent | `[ "emailDigest" ]` | The digest item is suppressed and no email is created for it. |

Returning `[ "email", "emailDigest" ]` creates two independent delivery paths; it does not choose one based on the digest subscription. If both paths are enabled and the subscription is immediate, the recipient can receive two emails about the same update: the original Notification's `toEmail()` and the digest renderer's one-item email. With a scheduled subscription, they can receive an individual email now and the update again in a later summary. Turning the digest off does not disable the separate ordinary-email route, which follows its own preferences.

The definition's `emailChannel: "email"` identifies the transport used by the digest pipeline. Configuring that transport does not mean adding `email` to the source Notification's `via()`.

An order receipt is a separate `OrderConfirmedNotification` whose `via()` returns `[ "email" ]`. Thus the application can offer receipts and product updates while each Notification has one email delivery path. Use both channels on a single Notification only when the product deliberately needs two distinct messages from that occurrence; the product-update example has no such requirement.

### Why use an immediate digest?

Imagine a catalog application where Mia follows camera products and also buys them. A new lens listing and an order receipt are different email products, even when both arrive immediately:

| Product | Delivery choice | Why it fits |
| --- | --- | --- |
| An order receipt: "Your order #1842 is confirmed" | Ordinary immediate email | An `OrderConfirmedNotification` supplies its own `toEmail()` with the purchased items, totals, and order link. Its content describes that completed transaction. |
| A followed-product update: "A new lens matches your interests" | Immediate digest | A `productUpdates` subscription sends one eligible update through `ProductDigestRenderer`. It uses the feed's consent, current catalog visibility, item selection, and unsubscribe rules. |
| Order receipts plus followed-product updates | Both email products | Mia can receive receipts for her purchases and separately opt into the update feed. Unsubscribing from `productUpdates` changes the feed, while order-message preferences remain independent. |

For the update feed, Mia might choose "As they happen" while another subscriber chooses "Weekly." The immediate subscriber receives a one-item digest; the weekly subscriber receives a batch through the same renderer. The application publishes one kind of item and maintains one set of feed rules, rather than a second immediate-email implementation. If the product only offers "As they happen," its preference UI can be On/Off and its definition can omit the calendar schedule, as shown below.

The current-content check matters here: a lens that has been withdrawn before transport should be omitted from the discovery feed. An order receipt has a different purpose: it describes what Mia purchased, using the order's saved details. Each product needs its own eligibility and consent rules.

Choose ordinary immediate email for an event-specific message when you do not need a named update stream or shared digest rendering. Choose an immediate digest when the message belongs to such a stream, whether or not you currently offer a scheduled summary. Both can use Megaphone's durable email transport, retries, and deduplication; those features alone are not a reason to choose the digest pipeline.

Supporting both products does not mean routing one update to both `email` and `emailDigest`. In this example, an order confirmation publishes the receipt and a new matching listing publishes the feed item. If one occurrence legitimately requires two messages, give each a distinct purpose and preference rule; otherwise choose the one that serves the recipient's need.

### An immediate-only digest policy

An application that wants the digest renderer for every individual item does not need to support scheduled Digest as another user choice. Omit the calendar schedule, use an immediate subscription, and keep `via()` returning only `[ "emailDigest" ]`:

```cfml
moduleSettings.megaphone.digests.productUpdates = {
    "emailChannel": "email",
    "policy": "ImmediateProductDigestPolicy",
    "renderer": "ProductDigestRenderer"
};

digests.setSubscription(
    notifiable = user,
    digestName = "productUpdates",
    mode = "immediate"
);
```

For this product, the preference UI can simply expose On/Off: On stores `immediate` and Off calls `unsubscribe()`. No calendar schedule, second delivery mode in the UI, second email Notification, or separate immediate renderer is needed. The module's existing delivery maintenance task still recovers pending work, and queue workers process immediate deliveries without a calendar wait.

`ImmediateProductDigestPolicy` can explicitly allow only immediate subscriptions:

```cfml
component {
    property name="consent" inject="ConsentService";
    property name="catalog" inject="ProductService";

    public boolean function canCollect( required any notifiable, required struct definition, required struct item ) {
        return allowsEmail( arguments.notifiable, arguments.definition ) &&
            isEligible( arguments.notifiable, arguments.definition, arguments.item );
    }

    public boolean function canSend( required any notifiable, required struct definition, required struct subscription ) {
        return arguments.subscription.mode == "immediate" &&
            allowsEmail( arguments.notifiable, arguments.definition );
    }

    public boolean function isEligible( required any notifiable, required struct definition, required struct item ) {
        return variables.catalog.isVisibleTo( arguments.item.data.productId, arguments.notifiable.getNotifiableId() );
    }

    private boolean function allowsEmail( required any notifiable, required struct definition ) {
        return variables.consent.allowsEmail( arguments.notifiable.getNotifiableId() ) &&
            variables.consent.allowsDigest( arguments.notifiable.getNotifiableId(), arguments.definition.name );
    }
}
```

The `immediate` subscription sets the timing; this policy authorizes collection and sending. These are example application services, not built-in Megaphone components. If the same consent rules apply to both timings, reuse `ProductDigestPolicy` instead of adding a separate policy class. The same `ProductDigestRenderer` receives an `items` array containing one item and a batch with `mode="immediate"`.

Immediate items retain their stable item, batch, and delivery identities. A replay cannot create a second email. Selection may discard the item, and consent, mode, generation, and eligibility are checked again before transport. Retryable or ambiguous outcomes use the existing durable delivery rules; Immediate does not bypass them. Changing to Immediate does not send previously accumulated scheduled items.

### When to offer both timings

Offer Immediate and Scheduled Digest as mutually exclusive choices when recipients want either each update as it happens or a daily/weekly summary. A subscription has one mode, so the same event is not automatically sent through both paths. Different products can also use different timings, such as immediate announcements and weekly product summaries.

Offering both timing choices still uses only `[ "emailDigest" ]` in the product-update Notification. The subscription picks Immediate or Scheduled Digest; adding `email` to `via()` would add another email rather than another timing choice. Ordinary transactional email, such as an order receipt, belongs to a separate Notification using `[ "email" ]`.

### Scheduling with ColdBox

Megaphone provides `config/Scheduler.cfc`, registered by ColdBox as `cbScheduler@megaphone`. For scheduled subscriptions it registers one native task for each digest/schedule/timezone combination, rather than one thread per subscriber. The task freezes one scheduled cutoff and dispatches its durable mail deliveries. A separate task checks pending deliveries and restores newly persisted schedule variants every minute.

Use the exact ColdBox frequency names:

```cfml
"schedule": "everyDayAt 09:00"
"schedule": "everyWeekOn 1 09:00"
"schedule": "everyMonth"
"schedule": { "cadence": "every", "arguments": [ 2, "hours" ] }
```

`cadence` names a native scheduled-task frequency method. Arguments are positional, in native order. A shortcut string separates its method and arguments with spaces. ColdBox uses Monday `1` through Sunday `7` for `everyWeekOn()`.

For advanced schedules, configure the named definition with a closure receiving the real ColdBox task:

```cfml
"schedule": ( task ) => task
    .onWeekdays( "09:00" )
    .withNoOverlaps()
    .when( () => productUpdatesEnabled() )
```

A named definition can also supply an unstarted `coldbox.system.async.tasks.ScheduledTask` instance as a template. Megaphone copies its frequency, constraints, and lifecycle callbacks into its own module task; its callable belongs to Megaphone. Prefer a closure for reusable templates, especially calendar schedules initialized well before registration. Do not call `start()` in the configuration closure.

Executable closures and task instances stay in the named definition. Subscriptions persist a reference to that definition, a JSON-safe shortcut/method-and-arguments override, or the frequency and constraints of an unstarted task instance. An instance supplied to `setSubscription(schedule=...)` must not contain executable callbacks; put those callbacks in the named definition. They do not serialize closures or thread/executor state into the database. This allows restart recovery. Re-register application-created definitions on every node and on restart before using their subscriptions.

`timezone` on a definition or subscription is applied to the native task using `setTimezone()`. A subscription's chosen zone takes precedence. A configuration closure can call `setTimezone()` when the definition does not supply `timezone`; otherwise omitted zones inherit the module scheduler. Frequency, constraints, daylight-saving behavior, and lifecycle callbacks follow the installed ColdBox version. Megaphone no longer supplies a separate DST/calendar implementation; review ColdBox's [scheduled task documentation](https://coldbox.ortusbooks.com/digging-deeper/promises-async-programming/scheduled-tasks-1) for its timezone caveats.

Add a new product digest after startup:

```cfml
digests.registerDigest( "weeklyAnnouncements", {
    "schedule": ( task ) => task.everyWeekOn( 5, "16:00" ),
    "timezone": "America/Denver",
    "emailChannel": "email",
    "policy": "AnnouncementDigestPolicy",
    "renderer": "AnnouncementDigestRenderer"
} );
```

A definition with a schedule registers and starts its task on the existing module scheduler. An immediate-only definition omits the schedule and needs no calendar task. Adding or changing a subscription also registers its schedule/timezone variant locally; the minute task discovers variants created on another node. Database locks and durable delivery leases coordinate workers. Digest definitions are application configuration, so `registerDigest()` rejects duplicate names rather than silently replacing a running schedule.

### Stable item identities and occurrence times

Use the helpers on `EmailDigestService`:

```cfml
var item = {
    "digestName": "productUpdates",
    "itemKey": digests.itemKey( [ "product.updated", savedEvent.getId(), 1 ] ),
    "occurredAt": digests.occurredAt( savedEvent.getOccurredDate() ),
    "data": { "productId": savedEvent.getProductId() }
};
```

`itemKey(parts)` hashes canonical JSON with SHA-256, producing a bounded 64-character identity. Use stable domain identifiers and a version: the same logical occurrence must supply the same parts on every retry. Different products or event versions need different parts. The digest/recipient scope is supplied by the subscription, so the same item key can be reused independently across recipients.

`occurredAt(date)` converts the original saved occurrence date to integer UTC epoch milliseconds. Reuse that saved date; calling `now()` during a retry changes the logical occurrence and conflicts with an existing identity.

### Supplying consent and eligibility

The definition's `policy` is a WireBox mapping or component implementing `IEmailDigestPolicy`, or the same methods:

| Method | What it checks |
| --- | --- |
| `canCollect(notifiable, definition, item)` | Whether this item may enter collection under the current preference and consent policy. |
| `canSend(notifiable, definition, subscription)` | Whether the recipient currently permits this named digest. |
| `isEligible(notifiable, definition, item)` | Whether the item is still visible and eligible for this recipient. |

Each method returns a boolean and performs local reads. Check authoritative preference and domain state rather than cached Notifiable fields or saved item content. Policy errors prevent a send. A global `queue.eligibilityPolicy` also runs for the internal `emailDigestBatch` event; make it recognize the batch reference and leave item decisions to the named policy.

For example, an application's `ProductDigestPolicy` can check its consent records and current catalog visibility:

```cfml
component {
    property name="consent" inject="ConsentService";
    property name="catalog" inject="ProductService";

    public boolean function canCollect( required any notifiable, required struct definition, required struct item ) {
        return canSend( arguments.notifiable, arguments.definition, {} ) &&
            variables.catalog.isVisibleTo( arguments.item.data.productId, arguments.notifiable.getNotifiableId() );
    }

    public boolean function canSend( required any notifiable, required struct definition, required struct subscription ) {
        return variables.consent.allowsEmail( arguments.notifiable.getNotifiableId() ) &&
            variables.consent.allowsDigest( arguments.notifiable.getNotifiableId(), arguments.definition.name );
    }

    public boolean function isEligible( required any notifiable, required struct definition, required struct item ) {
        return variables.catalog.isVisibleTo( arguments.item.data.productId, arguments.notifiable.getNotifiableId() );
    }
}
```

`ConsentService` and `ProductService` are example application services, not built-in Megaphone components. Missing products should return false from the visibility check. Consent is checked before selection and again immediately before transport.

Off, disabled, or denied items become suppression records. Their identities are not re-enabled by a later retry. Occurrences before the subscription's effective boundary are also suppressed. A changed preference cannot cause an old item to be collected again.

### Rendering the summary

The definition's `renderer` implements `IEmailDigestRenderer`, or its `render(notifiable, definition, batch, items)` method. Return a `BaseNotification` that implements `toEmail()`:

```cfml
component {
    property name="products" inject="ProductService";
    property name="unsubscribeLinks" inject="DigestUnsubscribeLinks";

    public BaseNotification function render(
        required any notifiable,
        required struct definition,
        required struct batch,
        required array items
    ) {
        return newDigestEmail().populate( {
            "digestName": arguments.definition.name,
            "products": arguments.items.map( ( item ) => variables.products.findVisible( item.data.productId, arguments.notifiable ) ),
            "unsubscribeUrl": variables.unsubscribeLinks.signedUrl( arguments.notifiable, arguments.definition.name )
        } );
    }

    private any function newDigestEmail() provider="ProductDigestEmail" {
    }
}
```

`ProductDigestEmail` is your application's Notification. Its `toEmail()` formats the supplied current products and signed unsubscribe URL. The renderer gathers current content; the returned Notification defines the actual email subject, view/body, and addressing. Megaphone assigns the stable batch ID to the rendered Notification and prepares it through the configured receipt-aware email channel.

Consent, subscription generation, and item eligibility are checked again after rendering, immediately before transport starts. If eligibility changed during rendering, the prepared message is discarded and rebuilt on retry. An item omitted from a batch never rejoins that batch. An empty eligible batch is suppressed without sending. Once transport starts, a preference change cannot retract that Provider request.

### Choosing the items

Selection happens once while freezing a scheduled cutoff or a new immediate item, after current consent and item eligibility checks. The default keeps all eligible candidates in descending `occurredAt` order, then item-key order. Configure `selectItems` as a closure or a WireBox component with `selectItems(notifiable, definition, items)`:

```cfml
"selectItems": ( notifiable, definition, items ) => items.isEmpty() ? [] : items.slice( 1, min( 10, items.len() ) )
```

This selects the ten newest eligible items. A component can instead choose by relevance, remove duplicates for the same product, or omit stale content. Return an array drawn from the supplied items, with each item appearing once. Foreign, ineligible, or duplicate identities are rejected. Return `[]` for no email.

All unselected candidates before this cutoff receive permanent `discarded` records. They do not remain pending for another digest, and publication retries do not re-enable them. Keep their identity records when pruning payload data. Items admitted at or after the cutoff belong to the next scheduled occurrence, because they were not candidates for this one. Retries use the frozen selection and may only remove newly ineligible members; they do not run selection again or pull replacements.

### Dispatching scheduled batches

The module scheduler prepares and dispatches batches automatically. `dispatchDue()` handles pending digest deliveries and expired digest leases only; it does not create a cutoff or send unrelated notification channels. Invoke it outside application transactions when operating a worker manually.

For an explicit scheduled boundary or a controlled test, `prepareDigest(digestName, cutoff, timezone, schedule, limit=100)` freezes one bounded group without Provider I/O. `cutoff` is integer UTC epoch milliseconds. `timezone` and `schedule` identify the subscription group; omitted values use the named defaults. Nonempty results have a `deliveryId`; dispatch those IDs through `NotificationDeliveryService` after commit.

The scheduler drains each group in bounded transactions. The subscription row lock makes overlapping calls for the same scheduled cutoff safe. Batch IDs, cutoffs, and original membership stay stable during retries. An empty batch records the cutoff without creating mail work. After downtime, the next native task occurrence selects accumulated candidates once; Megaphone does not synthesize an email for every missed period.

### Inspecting collection and email

`NotificationPublication.getCollections()` returns `{id, status, created}` admission results. An item can be `collected`, `batched`, `discarded`, or `suppressed`; these states do not mean an email was sent. Immediate admissions also expose `batchId` and `deliveryId` when a nonempty one-item batch is created. Its publication includes that delivery in `getDeliveries()` and can enqueue it without waiting for the schedule. Event admission links let overlapping events refer to one item and let either event replay return its original collection identity.

A nonempty batch has a separate durable email delivery. Inspect its Provider outcome and attempts using `NotificationDeliveryService.getDelivery(batch.deliveryId)` and `getAttempts(batch.deliveryId)`. Batch state describes frozen membership; email acceptance is recorded on the delivery.

Confirmed retryable failures use the same batch and delivery identity. Unknown outcomes remain `ambiguous` and do not automatically resend. See [Delivery Operations](https://megaphone.ortusbooks.com/notification-storage-and-delivery/delivery-operations) for acceptance receipts, authoritative rejection reconciliation, and bounded operator recovery. A plain cbMailServices success callback is insufficient for durable acceptance.

### Unsubscribing from one digest

After validating an application-signed link bound to the recipient and digest name, call:

```cfml
digests.unsubscribe( notifiable = user, digestName = "productUpdates" );
```

This turns off only `productUpdates` and suppresses its obsolete collection. It does not change other digest subscriptions, general channel preferences, push registrations, or transactional email settings. The application supplies the handler, signature validation, and authorization.

Keep stable item identities when pruning old content. Deleting collection identities would allow duplicate admission and historical replay. See [EmailDigestService](https://megaphone.ortusbooks.com/reference/emaildigestservice) for the public operations and return values.

### Why storage is shared

`storage.digests` belongs to the shared digest service, which is used by collection providers and the scheduler. It accepts `datasource`, `queryOptions`, subscription `table`, and `itemsTable`, `batchesTable`, and `admissionsTable`. Configuring it on each collection Provider would make the scheduler's store ambiguous when multiple channels use different settings.

The digest, event, and delivery stores must resolve to the same datasource. Freezing items, recording the batch, creating the durable email event/delivery, and attaching that delivery all commit in one transaction. A different datasource cannot preserve this guarantee with the current design and is rejected before batch creation. Separate databases would need an outbox transfer and idempotent reconciliation, not a second datasource option alone.

Setting a subscription to `immediate` affects future items only. Publishing a future item through `emailDigest` creates a one-item batch rendered by the named digest renderer, rather than routing the source Notification through ordinary `toEmail()`.
