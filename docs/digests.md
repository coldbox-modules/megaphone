# Digests across delivery channels

A digest collects notification items and determines when to publish a summary. The summary is an ordinary Megaphone Notification: its `via()` chooses delivery channels and its `toEmail()`, `toSMS()`, or other provider formatters produce channel-specific content. No digest renderer or delivery channel belongs in a generic digest definition.

The 1.2.0 [email digest API](email-digests.md) remains supported. Its `EmailDigestProvider`, `toEmailDigest()`, `emailChannel`, renderer, and `setSubscription()` behavior remain unchanged. Generic definitions use `notification` instead of `emailChannel` and `renderer`; do not mix the definition formats.

## Install and configure

Apply `2026_10_18_120000_add_generic_digest_publications` after the existing digest migration through your application's migration ledger. It adds saved resume modes and a batch-to-summary publication table. The existing subscriptions, items, admissions, batches, and delivery history remain intact. `storage.digests` remains the configuration owner and must share the transactional datasource used by events and deliveries.

The migration uses default table names. If your application customizes them, apply equivalent changes using your own migration. The new table can be configured with `storage.digests.publicationsTable`; existing `table`, `itemsTable`, `batchesTable`, `admissionsTable`, `datasource`, and `queryOptions` settings remain supported.

CommuniArts might offer daily and weekly audition updates. Inside `moduleSettings.megaphone`:

```cfml
channels = {
    // Your existing receipt-aware email and SMS provider registrations go here.
    "dailyAuditions": {
        "provider": "DigestProvider@megaphone",
        "properties": { "digestName": "dailyAuditions" }
    },
    "weeklyAuditions": {
        "provider": "DigestProvider@megaphone",
        "properties": { "digestName": "weeklyAuditions" }
    }
};

digests = {
    "dailyAuditions": {
        "schedule": "everyDayAt 09:00",
        "policy": "AuditionDigestPolicy",
        "notification": "DailyAuditionsNotification"
    },
    "weeklyAuditions": {
        "schedule": "everyWeekOn 1 09:00",
        "policy": "AuditionDigestPolicy",
        "notification": "WeeklyAuditionsNotification"
    }
};
```

Channel names identify configured Provider instances. Both collection channels use `DigestProvider`, so both call `toDigest()`. They do not call `toDailyAuditions()` or `toWeeklyAuditions()`. `properties.digestName` determines the destination; the item cannot override it.

Schedules and timezones use the existing native ColdBox scheduler integration: shortcut strings, schedule closures, or unstarted scheduled-task templates. Per-subscription shortcuts and timezones are supported. `registerDigest()` adds definitions to the existing scheduler after application startup. Separate digest definitions may use different summary classes or share the same class.

## Subscribe and collect

Megaphone stores the operational subscriptions. CommuniArts does not need to store another copy of the daily/weekly preference. Subscriptions remain independent: adding weekly does not stop daily automatically. Use a transfer when the application offers them as mutually exclusive choices:

```cfml
var digests = wirebox.getInstance( "DigestService@megaphone" );
digests.addSubscription(
    notifiable = user,
    digestName = "dailyAuditions",
    timezone = "America/Denver"
);
```

A missing or stopped subscription suppresses collection. Routing to a channel alone does not opt the recipient in. Suppressed item identities remain suppressed after subscription activation; old notifications are not replayed.

An excerpt from `AuditionPublishedNotification`:

```cfml
property name="digests" inject="DigestService@megaphone";

public array function via( required any notifiable ) {
    var routes = [];
    for ( var name in [ "dailyAuditions", "weeklyAuditions" ] ) {
        var subscription = variables.digests.getSubscription( arguments.notifiable, name );
        if ( !isNull( subscription ) && subscription.mode != "off" ) {
            routes.append( name );
        }
    }
    return routes;
}

public struct function toDigest( required any notifiable ) {
    return {
        "itemKey": variables.digests.itemKey( [ "audition.published", variables.publicationEventId, 1 ] ),
        "occurredAt": variables.digests.occurredAt( variables.publishedAt ),
        "data": { "auditionId": variables.auditionId }
    };
}
```

`itemKey()` hashes ordered, stable domain identity parts. Use the persisted publication event ID, not a fresh UUID on every attempt. `occurredAt()` converts the saved occurrence date into UTC epoch milliseconds. The payload is serialized data, not a live Notification object.

Publish this notification with `notify()`, `queue()`, or `queuePlan()` as usual. `plan()` remains read-only. One occurrence can enter multiple digests by returning multiple collection channels; multiple notification classes can contribute compatible items to one digest. Returning an ordinary delivery channel alongside a collection channel deliberately creates both immediate delivery and later collection.

The default selection retains all eligible items, newest occurrence first, with item-key ordering for ties. `selectItems` can select and order a subset. Unselected pre-cutoff items are permanently discarded rather than carried forward. Frozen membership can shrink when eligibility changes but does not acquire replacements.

## Summary notifications and delivery preferences

At the cutoff, Megaphone populates the configured Notification with `batchId`, `digestName`, `cutoffAt` (UTC epoch milliseconds), and `items`. Use the frozen cutoff when labeling the period so retries do not change its meaning. Each item includes `itemKey`, `occurredAt`, and application `data`, alongside its stored identity. These properties are durably captured for reconstruction.

For example, `DailyAuditionsNotification` can implement:

```cfml
public array function via( required any notifiable ) {
    return arguments.notifiable.getAuditionDeliveryChannels();
}

public Mail function toEmail( required any notifiable, required any newMail ) {
    return arguments.newMail(
        to = arguments.notifiable.getEmail(),
        from = "updates@example.com",
        subject = "Your daily audition updates",
        type = "html"
    ).setBody( variables.auditionViews.dailyEmail( variables.items, arguments.notifiable ) );
}

public string function toSMS( required any notifiable ) {
    return variables.auditionViews.dailyText( variables.items, arguments.notifiable );
}
```

`getAuditionDeliveryChannels()`, `auditionViews`, and the SMS formatter contract are illustrative application/provider APIs. Megaphone does not supply an SMS provider. Use the formatter signature and return type required by your selected provider. The audition view service can load current domain content from the stored IDs. The weekly Notification can use a different subject, grouping, and text while selecting the same delivery channels.

When `via()` returns `[ "email", "sms" ]`, there is one independent durable delivery per channel. A failed SMS retries without resending an accepted email. Both providers must support Megaphone's durable delivery contract.

Channels are chosen once when the summary is published. Current preferences can suppress pending deliveries; enabling a new channel afterward does not expand that publication. If no channels are selected, publication is still recorded and does not replay later. Generated summaries cannot route to collection channels.

## Lifecycle API

All methods identify a recipient using `notifiable` and a named collection using `digestName`. They return the stored subscription, except stopping a missing subscription returns null. Authorize the recipient in application code before calling them.

```cfml
// Create or reactivate; schedule/timezone inherit the definition by default.
digests.addSubscription( notifiable = user, digestName = "dailyAuditions" );

// Change timing while retaining eligible unsent membership.
digests.updateSubscription(
    notifiable = user,
    digestName = "dailyAuditions",
    timezone = "America/Chicago",
    schedule = "everyDayAt 17:00"
);

// Stop collection and invalidate unstarted delivery work.
digests.stopSubscription( notifiable = user, digestName = "dailyAuditions" );

// Resume saved settings for future items only.
digests.resumeSubscription( notifiable = user, digestName = "dailyAuditions" );
```

An identical active `addSubscription()` is a no-op. Conflicting active settings require `updateSubscription()`. Repeating stop or resume is harmless. Updating or resuming a missing subscription raises `Megaphone.Digests.SubscriptionMissing`. Updating a stopped subscription changes saved settings without activating it. Previously suppressed/discarded identities never revive. A stopped subscription migrated from 1.2.0 has no recorded previous mode and defaults to scheduled mode; use `updateSubscription(mode = "immediate")` before resuming an immediate-only legacy subscription.

Use `mode = "immediate"` on `addSubscription()` for immediate one-item summaries through the same output notification and durable delivery path. A calendar schedule is unnecessary for an immediate-only definition. To change between scheduled and immediate modes, stop the subscription, update its saved mode, then resume; ordinary schedule/timezone updates preserve pending items. An application choosing direct individual notifications instead must stop its old digest subscriptions explicitly.

## Transfer daily to weekly

Use a transfer when replacing one named collection with another:

```cfml
var result = digests.transferSubscription(
    notifiable = user,
    fromDigest = "dailyAuditions",
    toDigest = "weeklyAuditions",
    pendingItems = "transfer"
);
```

`pendingItems` is required and accepts exactly:

| Value | Pending source items |
|---|---|
| `transfer` | Move eligible, unsent items into the destination while retaining source admission tombstones. |
| `discard` | Suppress them; destination collection starts prospectively. |

The source stops and the destination activates in one transaction. A moved source item retains a `transferred` identity tombstone. An explicit transfer back can restore that moved item; ordinary publication retries cannot. This is distinct from permanently suppressed or discarded items. Existing destination subscriptions keep their schedule/timezone and pending items. A stopped destination resumes saved settings; a missing destination uses its definition defaults. A repeated transfer from a stopped source to an active destination is a no-op. Same-name transfers, missing sources, and invalid dispositions fail.

The result contains `source`, `destination`, and counts named `transferred`, `deduplicated`, `suppressed`, and `nontransferable`. Destination duplicates with identical content do not create another item or revive terminal identities. Reusing a key for different data or occurrence time aborts the transaction.

For `transfer`, the destination policy must explicitly approve the format through an optional hook:

```cfml
public boolean function canTransfer(
    required any notifiable,
    required struct sourceDefinition,
    required struct destinationDefinition,
    required array items
) {
    return listFindNoCase( "dailyAuditions,weeklyAuditions", arguments.sourceDefinition.name ) > 0;
}
```

Implement the normal `IDigestPolicy` methods too: `canCollect(notifiable, definition, item)`, `canSend(notifiable, definition, subscription)`, and `isEligible(notifiable, definition, item)`. For auditions, check authoritative notification consent and whether the audition still exists and is visible to the recipient. These methods perform local reads and fail closed. The destination policy rechecks admission and eligibility for each transferred item; an ineligible item is suppressed. Missing transfer approval, policy errors, or incompatible content abort atomically. `discard` needs no format approval.

A transfer never recalls an external send. Once any delivery of the generated summary has started, the entire batch is nontransferable, including accepted or uncertain work. Remaining unstarted source deliveries are fenced off; in-flight outcomes remain available for reconciliation. This conservative rule avoids resending an email because a sibling SMS has not completed. Newly admitted destination work remains independent.

## Reliability and operations

The module scheduler owns cutoffs and delivery polling. A stable batch identity allows exactly one saved summary event and its initial audience; scheduler and publication retries do not expand either. The internal publication job records local processing; the linked summary event proves that summary work was saved. Neither proves that email or SMS was accepted. Channel delivery records contain actual provider outcomes and attempts.

Consent, subscription generation, recipient identity, and item eligibility are rechecked before transport. If membership changes during formatting, preparation is discarded and retried with reduced membership. Stop, update, transfer, collection, cutoffs, and transport starts coordinate through subscription locks. External sends occur after publication commits; call synchronous sends outside application transactions.

A schedule/timezone update invalidates obsolete unstarted batches and returns eligible unsent items to collection. Batches whose transport has begun are not regrouped. Resuming starts a new prospective boundary without replaying stopped work. Deleted recipients, empty eligible batches, and withdrawn auditions do not send.

`DigestService@megaphone` and `EmailDigestService@megaphone` resolve to the same module service. Legacy `setSubscription()` retains its original invalidation behavior; only the new lifecycle update API preserves pending membership. Existing email definitions continue using their renderer and configured email transport without requiring `via()` on rendered notifications.
