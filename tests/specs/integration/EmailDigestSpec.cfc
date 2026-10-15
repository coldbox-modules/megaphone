component extends="tests.specs.integration.DeliveryStoreSpec" {

    function beforeAll() {
        super.beforeAll();
        var binder = variables.injector.getBinder();
        for ( var name in [ "EmailDigestSchedule", "EmailDigestBatchNotification" ] ) {
            binder.map( name & "@megaphone" ).to( "megaphone.models.Digests." & name );
        }
        binder.map( "EmailDigestStore@megaphone" ).to( "megaphone.models.Storage.EmailDigestStore" );
        variables.digestStore = variables.injector.getInstance( "EmailDigestStore@megaphone" );
        variables.policy = new tests.resources.DigestPolicyFixture();
        variables.renderer = new tests.resources.DigestRendererFixture();
        variables.mail = new tests.resources.DigestMailProviderFixture();
        variables.config = {
            "digests": {
                "discovery": {
                    "schedule": "everyWeekOn 1 09:00",
                    "emailChannel": "receiptMail",
                    "policy": variables.policy,
                    "renderer": variables.renderer
                },
                "news": {
                    "schedule": "everyDayAt 11:00",
                    "emailChannel": "receiptMail",
                    "policy": variables.policy,
                    "renderer": variables.renderer
                }
            }
        };
        binder
            .map( "NotificationSnapshotHasher@megaphone" )
            .to( "megaphone.models.Delivery.NotificationSnapshotHasher" );
        binder.map( "NotificationRuntime@megaphone" ).toValue( new tests.resources.DigestRuntimeFixture() );
        binder
            .map( "EmailDigestService@megaphone" )
            .to( "megaphone.models.Digests.EmailDigestService" )
            .property( name = "settings", value = variables.config );
        variables.digests = variables.injector.getInstance( "EmailDigestService@megaphone" );
        // The delivery service from the superclass held the previous runtime; resolve a fresh instance.
        variables.operations = variables.injector.getInstance( "NotificationDeliveryService@megaphone" );
        prepareMock( variables.operations ).$property(
            "runtime",
            "variables",
            variables.injector.getInstance( "NotificationRuntime@megaphone" )
        );
        binder.map( "NotificationDeliveryService@megaphone" ).toValue( variables.operations );
        prepareMock( variables.digests ).$property( "deliveries", "variables", variables.operations );
        variables.notifications = variables.injector.getInstance( "NotificationService@megaphone" );
        variables.notifications.getChannels().receiptMail = variables.mail;
        binder.map( "EmailDigestProvider@megaphone" ).to( "megaphone.models.Providers.EmailDigestProvider" );
        binder.map( "EmailDigestBatchProvider@megaphone" ).to( "megaphone.models.Providers.EmailDigestBatchProvider" );
        binder.map( "NotificationPublication@megaphone" ).to( "megaphone.models.Delivery.NotificationPublication" );
        binder.map( "NotificationPlan@megaphone" ).to( "megaphone.models.Delivery.NotificationPlan" );
        variables.notifications.registerChannels( {
            "emailDigest": { "provider": "EmailDigestProvider@megaphone", "properties": {} },
            "emailDigestBatch": { "provider": "EmailDigestBatchProvider@megaphone", "properties": {} }
        } );
    }

    function run() {
        describe( "Named durable email digests", () => {
            beforeEach( () => {
                variables.owner = new tests.resources.InboxRecipient();
                variables.start = dateAdd( "d", -10, now() );
                variables.calendar = new megaphone.models.Digests.EmailDigestSchedule();
                variables.policy
                    .setConsent( true )
                    .setAdmission( true )
                    .setExcluded( {} );
                variables.renderer.setRendered( [] ).setOnRender( javacast( "null", "" ) );
                variables.mail.setOutcome( "accepted" ).setSent( [] );
                variables.injector
                    .getInstance( "NotificationRuntime@megaphone" )
                    .setQueueAdapter( javacast( "null", "" ) );
            } );
            aroundEach( ( spec ) => {
                transaction {
                    try {
                        variables.subscription = variables.digests.setSubscription(
                            notifiable = variables.owner,
                            digestName = "discovery",
                            mode = "digest",
                            timezone = "America/Denver",
                            clock = variables.start
                        );
                        spec.body();
                    } finally {
                        transactionRollback();
                    }
                }
            } );
            it( "sends immediate through the digest renderer with a single collection route", () => {
                variables.digests.setSubscription(
                    notifiable = variables.owner,
                    digestName = "discovery",
                    mode = "immediate",
                    clock = variables.start
                );
                variables.notifications.notify(
                    variables.owner,
                    new tests.resources.DigestNotificationFixture(),
                    item( "instant" )
                );
                variables.notifications.notify(
                    variables.owner,
                    new tests.resources.DigestNotificationFixture(),
                    item( "instant" )
                );
                expect( variables.renderer.getRendered().len() ).toBe( 1 );
                expect( variables.mail.getSent().len() ).toBe( 1 );
                expect( variables.mail.getSent()[ 1 ].keys ).toBe( [ "instant" ] );
            } );
            it( "queues and replays the same one-item immediate delivery", () => {
                variables.digests.setSubscription(
                    notifiable = variables.owner,
                    digestName = "discovery",
                    mode = "immediate",
                    clock = variables.start
                );
                var queue = new tests.resources.DurableQueueFixture();
                variables.injector.getInstance( "NotificationRuntime@megaphone" ).setQueueAdapter( queue );
                var plan = variables.notifications.plan(
                    variables.owner,
                    new tests.resources.DigestNotificationFixture(),
                    item( "queued-immediate" ),
                    { "eventKey": createUUID() }
                );
                var first = variables.notifications.queuePlan( plan );
                var replay = variables.notifications.queuePlan( plan );
                expect( first.getDeliveries().len() ).toBe( 1 );
                expect( first.getCollections()[ 1 ].status ).toBe( "batched" );
                expect( replay.getDeliveries()[ 1 ].getId() ).toBe( first.getDeliveries()[ 1 ].getId() );
                expect( queue.getDeliveries().len() ).toBe( 1 );
                expect( variables.mail.getSent().len() ).toBe( 0 );
                variables.operations.dispatch( first.getDeliveries()[ 1 ].getId() );
                expect( variables.mail.getSent().len() ).toBe( 1 );
            } );
            it( "suppresses immediate consent changes during rendering before transport", () => {
                variables.digests.setSubscription(
                    notifiable = variables.owner,
                    digestName = "discovery",
                    mode = "immediate",
                    clock = variables.start
                );
                variables.renderer.setOnRender( () => variables.digests.unsubscribe( variables.owner, "discovery" ) );
                variables.notifications.notify(
                    variables.owner,
                    new tests.resources.DigestNotificationFixture(),
                    item( "instant-opt-out" )
                );
                expect( variables.renderer.getRendered().len() ).toBe( 1 );
                expect( variables.mail.getSent().len() ).toBe( 0 );
            } );
            it( "preserves an immediate batch on confirmed retry and quarantines unknown outcomes", () => {
                variables.digests.setSubscription(
                    notifiable = variables.owner,
                    digestName = "discovery",
                    mode = "immediate",
                    clock = variables.start
                );
                var collected = collect( "retry-instant" );
                variables.mail.setOutcome( "retryable" );
                expect( variables.operations.dispatch( collected.deliveryId ).getStatus() ).toBe( "retryable" );
                expect( collect( "retry-instant" ).deliveryId ).toBe( collected.deliveryId );
                variables.mail.setOutcome( "throw" );
                expect( variables.operations.dispatch( collected.deliveryId ).getStatus() ).toBe( "ambiguous" );
                expect( variables.operations.dispatch( collected.deliveryId ).getStatus() ).toBe( "ambiguous" );
                expect( variables.mail.getSent().len() ).toBe( 2 );
                expect( variables.mail.getSent()[ 1 ].keys ).toBe( variables.mail.getSent()[ 2 ].keys );
            } );
            it( "keeps separate immediate items at the same millisecond and fences opt-out", () => {
                variables.digests.setSubscription(
                    notifiable = variables.owner,
                    digestName = "discovery",
                    mode = "immediate",
                    clock = variables.start
                );
                var first = collect( "one" );
                var second = collect( "two" );
                expect( first.deliveryId ).notToBe( second.deliveryId );
                variables.digests.unsubscribe( variables.owner, "discovery" );
                expect( variables.operations.dispatch( first.deliveryId ).getStatus() ).toBe( "suppressed" );
                expect( variables.operations.dispatch( second.deliveryId ).getStatus() ).toBe( "suppressed" );
                expect( variables.mail.getSent().len() ).toBe( 0 );
            } );
            it( "allows immediate-only definitions without a calendar schedule", () => {
                variables.config.digests.instant = {
                    "emailChannel": "receiptMail",
                    "policy": variables.policy,
                    "renderer": variables.renderer
                };
                try {
                    variables.digests.setSubscription(
                        notifiable = variables.owner,
                        digestName = "instant",
                        mode = "immediate",
                        clock = variables.start
                    );
                    var collected = collect( "one", "instant" );
                    expect( variables.operations.dispatch( collected.deliveryId ).getStatus() ).toBe( "accepted" );
                    expect( () => variables.digests.setSubscription( variables.owner, "instant", "digest" ) ).toThrow( "Megaphone.Digests.InvalidSchedule" );
                } finally {
                    structDelete( variables.config.digests, "instant" );
                }
            } );
            it( "discards an immediate item rejected by selection without creating mail", () => {
                variables.digests.setSubscription(
                    notifiable = variables.owner,
                    digestName = "discovery",
                    mode = "immediate",
                    clock = variables.start
                );
                variables.config.digests.discovery.selectItems = ( notifiable, definition, items ) => [];
                try {
                    var collected = collect( "omit" );
                    expect( collected.status ).toBe( "discarded" );
                    expect( len( collected.deliveryId ?: "" ) ).toBe( 0 );
                    expect( collect( "omit" ).status ).toBe( "discarded" );
                    expect( variables.mail.getSent().len() ).toBe( 0 );
                } finally {
                    structDelete( variables.config.digests.discovery, "selectItems" );
                }
            } );
            it( "collects through notify without email delivery or mail attempts", () => {
                variables.notifications.notify(
                    variables.owner,
                    new tests.resources.DigestNotificationFixture(),
                    item( "one" )
                );
                expect( variables.mail.getSent().len() ).toBe( 0 );
                expect( variables.deliveries.due().len() ).toBe( 0 );
                var batches = variables.digests.prepareDigest( "discovery", cutoff(), "America/Denver" );
                expect( batches.len() ).toBe( 1 );
                // Notification collected now was admitted after this historical cutoff.
                expect( batches[ 1 ].state ).toBe( "empty" );
            } );
            it( "freezes a stable batch and sends exactly one receipt-aware email", () => {
                collect( "one" );
                collect( "two" );
                var batch = freeze();
                var membership = variables.digestStore.items( batch.id );
                expect( membership.len() ).toBe( 2 );
                expect( variables.deliveries.attempts( batch.deliveryId ).len() ).toBe( 0 );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "accepted" );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "accepted" );
                expect( variables.mail.getSent().len() ).toBe( 1 );
                expect( variables.mail.getSent()[ 1 ].keys.sort( "text" ) ).toBe( [ "one", "two" ] );
                expect( variables.digestStore.items( batch.id ).map( ( row ) => row.id ) ).toBe(
                    membership.map( ( row ) => row.id )
                );
            } );
            it( "keeps named subscriptions, schedules and unsubscribe independent", () => {
                var news = variables.digests.setSubscription(
                    notifiable = variables.owner,
                    digestName = "news",
                    mode = "digest",
                    clock = variables.start
                );
                expect( news.schedule ).notToBe( variables.subscription.schedule );
                collect( "same" );
                collect( "same", "news" );
                variables.digests.unsubscribe( variables.owner, "discovery" );
                expect( variables.digests.getSubscription( variables.owner, "news" ).mode ).toBe( "digest" );
                expect( variables.digests.getSubscription( variables.owner, "discovery" ).mode ).toBe( "off" );
                var batches = variables.digests.prepareDigest( "news", variables.calendar.epoch(), news.timezone );
                expect( batches.len() ).toBe( 1 );
                expect( variables.operations.dispatch( batches[ 1 ].deliveryId ).getStatus() ).toBe( "accepted" );
                expect( variables.renderer.getRendered()[ 1 ].digestName ).toBe( "news" );
            } );
            it( "suppresses an opt-out after collection and after freezing", () => {
                collect( "one" );
                var batch = freeze();
                variables.digests.unsubscribe( variables.owner, "discovery" );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "suppressed" );
                expect( variables.mail.getSent().len() ).toBe( 0 );
                expect( variables.deliveries.find( batch.deliveryId ).transportCount ).toBe( 0 );
            } );
            it( "rechecks consent at dispatch and omits empty eligible batches", () => {
                collect( "one" );
                var batch = freeze();
                variables.policy.setConsent( false );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "suppressed" );
                expect( variables.mail.getSent().len() ).toBe( 0 );
            } );
            it( "removes changed eligibility before rendering and never restores omitted membership", () => {
                collect( "hidden" );
                collect( "visible" );
                var batch = freeze();
                variables.policy.setExcluded( { "hidden": true } );
                variables.mail.setOutcome( "retryable" );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "retryable" );
                variables.policy.setExcluded( {} );
                expect(
                    variables.digests.prepareBatch( variables.owner, batch.id ).items.map( ( row ) => row.itemKey )
                ).toBe( [ "visible" ] );
                expect( variables.mail.getSent()[ 1 ].keys ).toBe( [ "visible" ] );
            } );
            it( "does not send when every item becomes ineligible", () => {
                collect( "hidden" );
                var batch = freeze();
                variables.policy.setExcluded( { "hidden": true } );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "suppressed" );
                expect( variables.renderer.getRendered().len() ).toBe( 0 );
                expect( variables.deliveries.find( batch.deliveryId ).transportCount ).toBe( 0 );
            } );
            it( "applies delivery-mode changes prospectively without replay", () => {
                collect( "old" );
                var changed = dateAdd( "h", 2, variables.start );
                variables.digests.setSubscription(
                    notifiable = variables.owner,
                    digestName = "discovery",
                    mode = "immediate",
                    clock = changed
                );
                var off = collect( "immediate", "discovery", dateAdd( "h", 3, variables.start ) );
                expect( off.status ).toBe( "batched" );
                variables.subscription = variables.digests.setSubscription(
                    notifiable = variables.owner,
                    digestName = "discovery",
                    mode = "digest",
                    timezone = "America/Denver",
                    clock = dateAdd( "h", 4, variables.start )
                );
                expect( collect( "old" ).status ).toBe( "suppressed" );
                expect( collect( "immediate", "discovery", dateAdd( "h", 3, variables.start ) ).status ).toBe( "suppressed" );
                collect( "new", "discovery", dateAdd( "h", 5, variables.start ) );
                var batch = freeze();
                expect( variables.digestStore.items( batch.id ).map( ( row ) => row.itemKey ) ).toBe( [ "new" ] );
            } );
            it( "accepts a native subscription schedule and inherits its timezone", () => {
                var template = new coldbox.system.async.tasks.ScheduledTask( "override", {} )
                    .setTimezone( "Europe/London" )
                    .everyMonthOn( 2, "10:00" );
                var changed = variables.digests.setSubscription(
                    notifiable = variables.owner,
                    digestName = "discovery",
                    mode = "digest",
                    schedule = template,
                    clock = variables.start
                );
                expect( changed.timezone ).toBe( "Europe/London" );
                expect( changed.schedule.nativeTask.dayOfTheMonth ).toBe( 2 );
                expect( changed.generation ).toBe( variables.subscription.generation + 1 );
            } );
            it( "preserves collection on a repeated identical subscription update", () => {
                collect( "one" );
                var same = variables.digests.setSubscription(
                    notifiable = variables.owner,
                    digestName = "discovery",
                    mode = "digest",
                    timezone = "America/Denver"
                );
                expect( same.generation ).toBe( variables.subscription.generation );
                expect( variables.digestStore.items( freeze().id ).len() ).toBe( 1 );
            } );
            it( "deduplicates overlapping admissions and rejects conflicting identity reuse", () => {
                var first = collect( "one" );
                var second = collect( "one" );
                expect( second.id ).toBe( first.id );
                expect( second.created ).toBeFalse();
                expect( variables.digestStore.items( freeze().id ).len() ).toBe( 1 );
                expect( () => variables.digests.collect(
                    notifiable = variables.owner,
                    digestName = "discovery",
                    itemKey = "one",
                    data = { "message": "changed" },
                    occurredAt = item( "one" ).occurredAt
                ) ).toThrow( "Megaphone.Digests.IdentityConflict" );
                expect( isNull( variables.digests.getSubscription( variables.owner, "discovery" ) ) ).toBeTrue();
            } );
            it( "assigns exact-cutoff and late admissions to the next batch", () => {
                collect( "before" );
                collect( "at", "discovery", dateFromEpoch( cutoff() ) );
                var batch = freeze();
                expect( variables.digestStore.items( batch.id ).map( ( row ) => row.itemKey ) ).toBe( [ "before" ] );
                collect( "late", "discovery", dateFromEpoch( cutoff() + 1000 ) );
                expect( variables.digestStore.items( batch.id ).len() ).toBe( 1 );
                variables.subscription = variables.digests.getSubscription( variables.owner, "discovery" );
                var next = freeze();
                expect( variables.digestStore.items( next.id ).map( ( row ) => row.itemKey ) ).toBe( [ "late", "at" ] );
            } );
            it( "advances an empty schedule without creating email work", () => {
                var batch = freeze();
                expect( batch.state ).toBe( "empty" );
                expect( len( batch.deliveryId ?: "" ) ).toBe( 0 );
                expect( variables.mail.getSent().len() ).toBe( 0 );
                expect( variables.digests.prepareDigest( "discovery", batch.cutoffAt, "America/Denver" ).len() ).toBe(
                    0
                );
            } );
            it( "retries confirmed rejection with the same batch and bounded transport attempts", () => {
                collect( "one" );
                var batch = freeze();
                variables.mail.setOutcome( "retryable" );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "retryable" );
                variables.mail.setOutcome( "accepted" );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "accepted" );
                expect( variables.mail.getSent().len() ).toBe( 2 );
                expect( variables.deliveries.find( batch.deliveryId ).transportCount ).toBe( 2 );
                expect( variables.mail.getSent()[ 2 ].id ).toBe( batch.deliveryId );
                expect( variables.mail.getSent()[ 2 ].keys ).toBe( variables.mail.getSent()[ 1 ].keys );
            } );
            it( "quarantines uncertain sends until explicit authoritative receipt reconciliation", () => {
                collect( "one" );
                var batch = freeze();
                variables.mail.setOutcome( "throw" );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "ambiguous" );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "ambiguous" );
                expect( variables.mail.getSent().len() ).toBe( 1 );
                expect(
                    variables.operations.reconcileAccepted( batch.deliveryId, ( work ) => {
                        return { "accepted": true, "providerReference": "verified-receipt" };
                    } )
                ).toBeTrue();
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "accepted" );
            } );
            it( "suppresses opt-out during rendering before transport starts", () => {
                collect( "one" );
                var batch = freeze();
                variables.renderer.setOnRender( () => variables.digests.unsubscribe( variables.owner, "discovery" ) );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "suppressed" );
                expect( variables.mail.getSent().len() ).toBe( 0 );
                expect( variables.deliveries.find( batch.deliveryId ).transportCount ).toBe( 0 );
            } );
            it( "defers a rendered batch when eligibility changes during rendering", () => {
                collect( "one" );
                collect( "two" );
                var batch = freeze();
                variables.renderer.setOnRender( () => variables.policy.setExcluded( { "one": true } ) );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "retryable" );
                expect( variables.mail.getSent().len() ).toBe( 0 );
                expect( variables.deliveries.find( batch.deliveryId ).transportCount ).toBe( 0 );
            } );
            it( "fences overlapping workers and marks an expired started send ambiguous", () => {
                collect( "one" );
                var batch = freeze();
                var first = variables.deliveries.claim( batch.deliveryId );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "busy" );
                expect( variables.deliveries.startTransport( batch.deliveryId, first.token ) ).toBeTrue();
                variables.deliveries.recoverExpired( clock = dateAdd( "s", 61, now() ) );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "ambiguous" );
                expect( variables.mail.getSent().len() ).toBe( 0 );
            } );
            it( "requires authoritative rejection evidence before retrying an uncertain send", () => {
                collect( "one" );
                var batch = freeze();
                variables.mail.setOutcome( "throw" );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "ambiguous" );
                expect(
                    variables.operations.reconcileNotAccepted( batch.deliveryId, ( work ) => {
                        return { "accepted": false, "providerReference": "verified-rejection" };
                    } )
                ).toBeTrue();
                variables.mail.setOutcome( "accepted" );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "accepted" );
                expect( variables.mail.getSent().len() ).toBe( 2 );
                expect( variables.deliveries.find( batch.deliveryId ).transportCount ).toBe( 2 );
                expect(
                    variables.operations.reconcileNotAccepted( batch.deliveryId, ( work ) => {
                        return { "accepted": false, "providerReference": "stale" };
                    } )
                ).toBeFalse();
            } );
            it( "rejects reconciliation without an authoritative provider reference", () => {
                collect( "one" );
                var batch = freeze();
                variables.mail.setOutcome( "throw" );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "ambiguous" );
                expect( () => variables.operations.reconcileNotAccepted( batch.deliveryId, ( work ) => {
                    return { "accepted": false };
                } ) ).toThrow( "Megaphone.Delivery.InvalidReceipt" );
            } );
            it( "keeps the scheduler scoped to digest deliveries", () => {
                var past = dateAdd( "n", -5, now() );
                var event = variables.events.record(
                    namespace = "ordinary",
                    eventKey = createUUID(),
                    version = 1,
                    type = "email",
                    payload = {},
                    payloadHash = "ordinary"
                );
                var work = variables.deliveries.enqueue(
                    eventId = event.id,
                    recipientType = "User",
                    recipientId = "other",
                    channel = "email",
                    routingData = {},
                    routingHash = "ordinary",
                    availableDate = past
                );
                var lease = variables.deliveries.claim( work.id, 60, 5, past );
                variables.deliveries.startTransport( work.id, lease.token, past );
                variables.digests.dispatchDue();
                expect( variables.deliveries.find( work.id ).state ).toBe( "processing" );
            } );
            it( "invalidates pending membership when the confirmed timezone changes", () => {
                collect( "old" );
                var batch = freeze();
                var changed = variables.digests.setSubscription(
                    notifiable = variables.owner,
                    digestName = "discovery",
                    mode = "digest",
                    timezone = "UTC"
                );
                expect( changed.generation ).toBe( variables.subscription.generation + 1 );
                expect( changed.lastCutoffAt ).toBeLTE( variables.calendar.epoch() );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "suppressed" );
            } );
            it( "fails closed for absent subscription and explicit admission denial", () => {
                var other = new tests.resources.InboxRecipient();
                expect(
                    variables.digests.collect(
                        notifiable = other,
                        digestName = "discovery",
                        itemKey = "absent",
                        data = {},
                        occurredAt = variables.calendar.epoch()
                    ).status
                ).toBe( "suppressed" );
                variables.policy.setAdmission( false );
                var denied = collect( "denied" );
                expect( denied.status ).toBe( "suppressed" );
                variables.policy.setAdmission( true );
                expect( collect( "denied" ).status ).toBe( "suppressed" );
            } );
            it( "discards unselected membership permanently rather than carrying overflow", () => {
                variables.config.digests.discovery.selectItems = ( notifiable, definition, items ) => items.isEmpty() ? [] : items.slice(
                    1,
                    1
                );
                try {
                    collect( "one" );
                    collect( "two" );
                    var first = freeze();
                    expect( variables.digestStore.items( first.id ).len() ).toBe( 1 );
                    variables.subscription = variables.digests.getSubscription( variables.owner, "discovery" );
                    var second = freeze();
                    expect( variables.digestStore.items( second.id ).len() ).toBe( 0 );
                    expect( second.state ).toBe( "empty" );
                    expect( collect( "two" ).status ).toBe( "discarded" );
                } finally {
                    structDelete( variables.config.digests.discovery, "selectItems" );
                }
            } );
            it( "preserves custom selection order through rendering and retry", () => {
                collect( "one" );
                collect( "two" );
                variables.config.digests.discovery.selectItems = ( notifiable, definition, items ) => [
                    items[ 2 ],
                    items[ 1 ]
                ];
                try {
                    var batch = freeze();
                    expect( variables.digestStore.items( batch.id ).map( ( item ) => item.itemKey ) ).toBe( [ "two", "one" ] );
                    variables.mail.setOutcome( "retryable" );
                    variables.operations.dispatch( batch.deliveryId );
                    expect( variables.mail.getSent()[ 1 ].keys ).toBe( [ "two", "one" ] );
                } finally {
                    structDelete( variables.config.digests.discovery, "selectItems" );
                }
            } );
            it( "rejects a different datasource before writing a batch", () => {
                collect( "one" );
                var properties = prepareMock( variables.digests ).$getProperty( "store", "variables" ).getProperties();
                properties.datasource = "unrelatedDatabase";
                try {
                    expect( () => freeze() ).toThrow( "Megaphone.Digests.CrossDatasource" );
                } finally {
                    structDelete( properties, "datasource" );
                }
                expect( collect( "one" ).status ).toBe( "collected" );
            } );
            it( "rejects foreign selector items before committing membership", () => {
                collect( "one" );
                variables.config.digests.discovery.selectItems = ( notifiable, definition, items ) => [
                    { "id": createUUID() }
                ];
                try {
                    expect( () => freeze() ).toThrow( "Megaphone.Digests.InvalidSelection" );
                } finally {
                    structDelete( variables.config.digests.discovery, "selectItems" );
                }
            } );
            it( "builds stable bounded item keys and converts original occurrence dates", () => {
                expect( variables.digests.itemKey( [ "product.published", "42", 1 ] ) ).toBe(
                    variables.digests.itemKey( [ "product.published", "42", 1 ] )
                );
                expect( variables.digests.itemKey( [ "a:b", "c" ] ) ).notToBe(
                    variables.digests.itemKey( [ "a", "b:c" ] )
                );
                expect( variables.digests.itemKey( [ "product.published", "42", 1 ] ).len() ).toBe( 64 );
                expect( variables.digests.occurredAt( variables.start ) ).toBe(
                    variables.calendar.epoch( variables.start )
                );
            } );
            it( "preserves overlapping event admissions and replays even when a later plan has no channels", () => {
                var first = variables.notifications.plan(
                    variables.owner,
                    new tests.resources.DigestNotificationFixture(),
                    item( "overlap" ),
                    { "eventKey": createUUID() }
                );
                var second = variables.notifications.plan(
                    variables.owner,
                    new tests.resources.DigestNotificationFixture(),
                    item( "overlap" ),
                    { "eventKey": createUUID() }
                );
                var admitted = variables.notifications.queuePlan( first );
                var overlap = variables.notifications.queuePlan( second );
                expect( overlap.getCollections()[ 1 ].id ).toBe( admitted.getCollections()[ 1 ].id );
                expect( overlap.getCollections()[ 1 ].created ).toBeFalse();
                var replay = variables.notifications.queuePlan( second );
                expect( replay.getCollections()[ 1 ].id ).toBe( admitted.getCollections()[ 1 ].id );
                variables.digests.unsubscribe( variables.owner, "discovery" );
                var empty = new megaphone.models.Delivery.NotificationPlan().configure( second.getMemento().event, [] );
                var suppressed = variables.notifications.queuePlan( empty );
                expect( suppressed.getCollections()[ 1 ].id ).toBe( admitted.getCollections()[ 1 ].id );
                expect( suppressed.getCollections()[ 1 ].status ).toBe( "suppressed" );
            } );
            it( "queuePlans preserves scalar collection admission and replay without queued transport", () => {
                var first = variables.notifications.plan(
                    variables.owner,
                    new tests.resources.DigestNotificationFixture(),
                    item( "bulk-collected-one" ),
                    { "eventKey": createUUID() }
                );
                var second = variables.notifications.plan(
                    variables.owner,
                    new tests.resources.DigestNotificationFixture(),
                    item( "bulk-collected-two" ),
                    { "eventKey": createUUID() }
                );
                var publications = variables.notifications.queuePlans( [ first, second ] );
                var replayed = variables.notifications.queuePlans( [ first, second ] );
                for ( var index = 1; index <= 2; index++ ) {
                    expect( publications[ index ].getCollections().len() ).toBe( 1 );
                    expect( publications[ index ].getCollections()[ 1 ].status ).toBe( "collected" );
                    expect( replayed[ index ].getCollections()[ 1 ].id ).toBe(
                        publications[ index ].getCollections()[ 1 ].id
                    );
                    expect( replayed[ index ].getCollections()[ 1 ].created ).toBeFalse();
                    expect( publications[ index ].getDeliveries() ).toBeEmpty();
                }
                expect( variables.mail.getSent() ).toBeEmpty();
            } );
            it( "admitPlans retains collection admission and replay even with a reference-capable adapter", () => {
                var queue = new tests.resources.BulkReferenceQueueFixture();
                variables.injector.getInstance( "NotificationRuntime@megaphone" ).setQueueAdapter( queue );
                var plan = variables.notifications.plan(
                    variables.owner,
                    new tests.resources.DigestNotificationFixture(),
                    item( "reference-fallback-collected" ),
                    { "eventKey": createUUID() }
                );
                variables.notifications.admitPlans( [ plan ] );
                var replay = variables.notifications.queuePlan( plan );
                expect( replay.getCollections().len() ).toBe( 1 );
                expect( replay.getCollections()[ 1 ].status ).toBe( "collected" );
                expect( replay.getCollections()[ 1 ].created ).toBeFalse();
                expect( queue.getReferences() ).toBeEmpty();
                expect( queue.getDeliveries() ).toBeEmpty();
                expect( variables.mail.getSent() ).toBeEmpty();
            } );
            it( "queuePlan returns collection independently of delivered email and deduplicates event replays", () => {
                // Admit now into a future schedule; no queue adapter or provider send is involved.
                var plan = variables.notifications.plan(
                    [ variables.owner, variables.owner ],
                    new tests.resources.DigestNotificationFixture(),
                    item( "queued" ),
                    { "eventKey": createUUID() }
                );
                var publication = variables.notifications.queuePlan( plan );
                var replay = variables.notifications.queuePlan( plan );
                expect( replay.getCollections()[ 1 ].id ).toBe( publication.getCollections()[ 1 ].id );
                expect( replay.getCollections()[ 1 ].created ).toBeFalse();
                expect( publication.getDeliveries().len() ).toBe( 0 );
                expect( publication.getCollections().len() ).toBe( 1 );
                expect( publication.getCollections()[ 1 ].status ).toBe( "collected" );
                expect( variables.mail.getSent().len() ).toBe( 0 );
            } );
        } );
    }

    private struct function item( required string key, string digestName = "discovery" ) {
        return {
            "digestName": arguments.digestName,
            "itemKey": arguments.key,
            "occurredAt": variables.calendar.epoch( dateAdd( "h", 1, variables.start ) ),
            "data": { "message": arguments.key }
        };
    }
    private struct function collect( required string key, string digestName = "discovery", date clock ) {
        if ( isNull( arguments.clock ) ) {
            arguments.clock = dateAdd( "h", 1, variables.start );
        }
        var entry = item( arguments.key, arguments.digestName );
        entry.occurredAt = variables.calendar.epoch( arguments.clock );
        return variables.digests.collect(
            notifiable = variables.owner,
            digestName = entry.digestName,
            itemKey = entry.itemKey,
            data = entry.data,
            occurredAt = entry.occurredAt,
            clock = arguments.clock
        );
    }
    private numeric function cutoff() {
        return variables.subscription.lastCutoffAt + 7 * 24 * 60 * 60 * 1000;
    }
    private struct function freeze() {
        return variables.digests.prepareDigest( "discovery", cutoff(), "America/Denver" )[ 1 ];
    }
    private date function dateFromEpoch( required numeric epoch ) {
        return createObject( "java", "java.util.Date" ).init( javacast( "long", arguments.epoch ) );
    }

}
