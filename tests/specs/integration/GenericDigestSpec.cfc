component extends="tests.specs.integration.EmailDigestSpec" {

    function beforeAll() {
        super.beforeAll();
        var binder = variables.injector.getBinder();
        variables.genericPolicy = new tests.resources.GenericDigestPolicyFixture();
        variables.presentation = new tests.resources.GenericDigestStateFixture();
        binder.map( "GenericDigestState@megaphone" ).toValue( variables.presentation );
        binder.map( "DailyAuditionsNotification" ).to( "tests.resources.GenericDigestSummaryFixture" );
        binder.map( "WeeklyAuditionsNotification" ).to( "tests.resources.GenericDigestSummaryFixture" );
        for ( var name in [ "dailyAuditions", "weeklyAuditions" ] ) {
            variables.config.digests[ name ] = {
                "schedule": name == "dailyAuditions" ? "everyDayAt 09:00" : "everyWeekOn 1 09:00",
                "notification": name == "dailyAuditions" ? "DailyAuditionsNotification" : "WeeklyAuditionsNotification",
                "policy": variables.genericPolicy
            };
        }
        binder
            .map( "GenericDigestService@megaphone" )
            .to( "megaphone.models.Digests.DigestService" )
            .property( name = "settings", value = variables.config );
        variables.generic = variables.injector.getInstance( "GenericDigestService@megaphone" );
        prepareMock( variables.generic ).$property( "deliveries", "variables", variables.operations );
        binder.map( "EmailDigestService@megaphone" ).toValue( variables.generic );
        binder.map( "DigestProvider@megaphone" ).to( "megaphone.models.Providers.DigestProvider" );
        binder.map( "DigestBatchProvider@megaphone" ).to( "megaphone.models.Providers.DigestBatchProvider" );
        binder.map( "DigestBatchNotification@megaphone" ).to( "megaphone.models.Digests.DigestBatchNotification" );
        variables.notifications.registerChannels( {
            "dailyAuditions": {
                "provider": "DigestProvider@megaphone",
                "properties": { "digestName": "dailyAuditions" }
            },
            "weeklyAuditions": {
                "provider": "DigestProvider@megaphone",
                "properties": { "digestName": "weeklyAuditions" }
            },
            "digestBatch": { "provider": "DigestBatchProvider@megaphone", "properties": {} }
        } );
        variables.summaryEmail = new tests.resources.GenericDigestProviderFixture( "summaryEmail" );
        variables.summarySMS = new tests.resources.GenericDigestProviderFixture( "summarySMS" );
        variables.notifications.getChannels().summaryEmail = variables.summaryEmail;
        variables.notifications.getChannels().summarySMS = variables.summarySMS;
    }

    function run() {
        describe( "Provider-independent digests", () => {
            beforeEach( () => {
                variables.owner = new tests.resources.InboxRecipient();
                variables.start = dateAdd( "d", -10, now() );
                variables.calendar = new megaphone.models.Digests.EmailDigestSchedule();
                variables.genericPolicy
                    .setConsent( true )
                    .setAdmission( true )
                    .setExcluded( {} )
                    .setTransferAllowed( true );
                variables.presentation
                    .setChannels( [ "summaryEmail", "summarySMS" ] )
                    .setFormatted( [] )
                    .setOnFormat( javacast( "null", "" ) );
                variables.summaryEmail.setOutcome( "accepted" ).setSent( [] );
                variables.summarySMS.setOutcome( "accepted" ).setSent( [] );
            } );
            aroundEach( ( spec ) => {
                transaction {
                    try {
                        spec.body();
                    } finally {
                        transactionRollback();
                    }
                }
            } );
            it( "uses named channels to call toDigest and publishes one summary with independent transports", () => {
                add();
                var first = publish( "one" );
                var replay = publish( "one", first.getEvent().getEventKey() );
                expect( replay.getCollections()[ 1 ].id ).toBe( first.getCollections()[ 1 ].id );
                expect( first.getDeliveries() ).toBeEmpty();
                publish( "two" );
                var batch = freezeGeneric();
                var publication = variables.generic.publishBatch( variables.owner, batch.id );
                expect( variables.generic.publishBatch( variables.owner, batch.id ).eventId ).toBe(
                    publication.eventId
                );
                expect( variables.operations.getDeliveriesForEvent( publication.eventId ).len() ).toBe( 2 );
                variables.generic.dispatchPublishedBatch( batch.id );
                expect( variables.summaryEmail.getSent().len() ).toBe( 1 );
                expect( variables.summarySMS.getSent().len() ).toBe( 1 );
                expect( variables.summarySMS.getSent()[ 1 ].data.keys.len() ).toBe( 2 );
                variables.generic.dispatchPublishedBatch( batch.id );
                expect( variables.summaryEmail.getSent().len() ).toBe( 1 );
            } );
            it( "keeps absent subscriptions off and does not replay suppressed items after activation", () => {
                var first = publish( "one" );
                expect( first.getCollections()[ 1 ].status ).toBe( "suppressed" );
                add();
                expect( publish( "one" ).getCollections()[ 1 ].status ).toBe( "suppressed" );
            } );
            it( "collects a single occurrence independently into multiple digests", () => {
                add();
                add( "weeklyAuditions" );
                var result = variables.notifications.queue(
                    variables.owner,
                    new tests.resources.GenericDigestSourceFixture(),
                    entry( "one", [ "dailyAuditions", "weeklyAuditions" ] ),
                    { "eventKey": createUUID() }
                );
                expect( result.getCollections().len() ).toBe( 2 );
                expect( result.getCollections()[ 1 ].id ).notToBe( result.getCollections()[ 2 ].id );
            } );
            it( "publishes immediate one-item summaries using normal channel routing", () => {
                variables.generic.addSubscription(
                    notifiable = variables.owner,
                    digestName = "dailyAuditions",
                    mode = "immediate",
                    timezone = "America/Denver",
                    clock = variables.start
                );
                variables.notifications.notify(
                    variables.owner,
                    new tests.resources.GenericDigestSourceFixture(),
                    entry( "one" )
                );
                expect( variables.summaryEmail.getSent().len() ).toBe( 1 );
                expect( variables.summarySMS.getSent().len() ).toBe( 1 );
            } );
            it( "uses destination preferences at publication and never expands an existing publication", () => {
                add();
                publish( "one" );
                var batch = freezeGeneric();
                variables.presentation.setChannels( [ "summarySMS" ] );
                var first = variables.generic.publishBatch( variables.owner, batch.id );
                variables.presentation.setChannels( [ "summaryEmail", "summarySMS" ] );
                variables.generic.publishBatch( variables.owner, batch.id );
                expect( variables.operations.getDeliveriesForEvent( first.eventId ).len() ).toBe( 1 );
            } );
            it( "records empty routing once without replaying items when channels become enabled", () => {
                add();
                publish( "one" );
                var batch = freezeGeneric();
                variables.presentation.setChannels( [] );
                var first = variables.generic.publishBatch( variables.owner, batch.id );
                variables.presentation.setChannels( [ "summaryEmail" ] );
                variables.generic.publishBatch( variables.owner, batch.id );
                expect( variables.operations.getDeliveriesForEvent( first.eventId ) ).toBeEmpty();
            } );
            it( "rejects recursive summary collection before committing a publication", () => {
                add();
                publish( "one" );
                var batch = freezeGeneric();
                variables.presentation.setChannels( [ "dailyAuditions" ] );
                expect( () => variables.generic.publishBatch( variables.owner, batch.id ) ).toThrow( "Megaphone.Digests.RecursiveCollection" );
            } );
            it( "retries failed transports without sending accepted channels again", () => {
                add();
                publish( "one" );
                var batch = freezeGeneric();
                variables.generic.publishBatch( variables.owner, batch.id );
                variables.summarySMS.setOutcome( "retryable" );
                variables.generic.dispatchPublishedBatch( batch.id );
                variables.summarySMS.setOutcome( "accepted" );
                variables.generic.dispatchPublishedBatch( batch.id );
                expect( variables.summaryEmail.getSent().len() ).toBe( 1 );
                expect( variables.summarySMS.getSent().len() ).toBe( 2 );
            } );
            it( "suppresses a stopped publication job before starting its transport attempt", () => {
                add();
                publish( "one" );
                var batch = freezeGeneric();
                variables.generic.stopSubscription( variables.owner, "dailyAuditions" );
                expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "suppressed" );
                expect( variables.deliveries.find( batch.deliveryId ).transportCount ).toBe( 0 );
            } );
            it( "suppresses remaining deliveries when stopped during formatting", () => {
                add();
                publish( "one" );
                var batch = freezeGeneric();
                variables.generic.publishBatch( variables.owner, batch.id );
                variables.presentation.setOnFormat( () => variables.generic.stopSubscription( variables.owner, "dailyAuditions" ) );
                variables.generic.dispatchPublishedBatch( batch.id );
                expect( variables.summaryEmail.getSent() ).toBeEmpty();
                expect( variables.summarySMS.getSent() ).toBeEmpty();
            } );
            it( "reprepares a channel when eligibility changes during formatting", () => {
                add();
                publish( "one" );
                publish( "two" );
                var batch = freezeGeneric();
                var publication = variables.generic.publishBatch( variables.owner, batch.id );
                variables.presentation.setChannels( [ "summaryEmail" ] );
                variables.presentation.setOnFormat( () => variables.genericPolicy.setExcluded( { "two": true } ) );
                variables.generic.dispatchPublishedBatch( batch.id );
                variables.presentation.setOnFormat( javacast( "null", "" ) );
                variables.injector
                    .getInstance( "QueryBuilder@qb" )
                    .from( "megaphone_deliveries" )
                    .where( "eventId", publication.eventId )
                    .where( "state", "retryable" )
                    .update( { "availableDate": dateAdd( "s", -1, now() ) } );
                variables.generic.dispatchPublishedBatch( batch.id );
                expect( variables.summaryEmail.getSent()[ 1 ].data.keys ).toBe( [ "one" ] );
            } );
            it( "preserves pending items across a schedule update and invalidates old publications", () => {
                add();
                publish( "one" );
                var old = freezeGeneric();
                variables.generic.publishBatch( variables.owner, old.id );
                var updated = variables.generic.updateSubscription(
                    notifiable = variables.owner,
                    digestName = "dailyAuditions",
                    schedule = "everyDayAt 17:00"
                );
                variables.generic.dispatchPublishedBatch( old.id );
                expect( variables.summaryEmail.getSent() ).toBeEmpty();
                expect( variables.digestStore.pending( updated.id ).len() ).toBe( 1 );
                expect( variables.digestStore.pending( updated.id )[ 1 ].state ).toBe( "collected" );
            } );
            it( "makes lifecycle operations idempotent and resumes only future collection", () => {
                var original = add();
                expect( add().generation ).toBe( original.generation );
                publish( "one" );
                var stopped = variables.generic.stopSubscription( variables.owner, "dailyAuditions" );
                expect( variables.generic.stopSubscription( variables.owner, "dailyAuditions" ).generation ).toBe(
                    stopped.generation
                );
                var resumed = variables.generic.resumeSubscription( variables.owner, "dailyAuditions" );
                expect( variables.generic.resumeSubscription( variables.owner, "dailyAuditions" ).generation ).toBe(
                    resumed.generation
                );
                expect( variables.digestStore.pending( resumed.id ) ).toBeEmpty();
            } );
            it( "transfers pending items, preserves destination timing and prevents source replay", () => {
                add();
                var destination = add( "weeklyAuditions" );
                publish( "one" );
                var result = variables.generic.transferSubscription(
                    variables.owner,
                    "dailyAuditions",
                    "weeklyAuditions",
                    "transfer"
                );
                expect( result.transferred ).toBe( 1 );
                expect( result.source.mode ).toBe( "off" );
                expect( result.destination.generation ).toBe( destination.generation );
                expect( variables.digestStore.pending( result.destination.id )[ 1 ].itemKey ).toBe( "one" );
                expect( publish( "one" ).getCollections()[ 1 ].status ).toBe( "transferred" );
                expect(
                    variables.generic.transferSubscription(
                        variables.owner,
                        "dailyAuditions",
                        "weeklyAuditions",
                        "transfer"
                    ).transferred
                ).toBe( 0 );
            } );
            it( "deduplicates destination identities and transfers into missing subscriptions", () => {
                add();
                publish( "one" );
                var result = variables.generic.transferSubscription(
                    variables.owner,
                    "dailyAuditions",
                    "weeklyAuditions",
                    "transfer"
                );
                expect( result.transferred ).toBe( 1 );
                variables.generic.resumeSubscription(
                    notifiable = variables.owner,
                    digestName = "dailyAuditions",
                    clock = variables.start
                );
                publish( "two" );
                variables.notifications.queue(
                    variables.owner,
                    new tests.resources.GenericDigestSourceFixture(),
                    entry( "two", [ "weeklyAuditions" ] ),
                    { "eventKey": createUUID() }
                );
                var second = variables.generic.transferSubscription(
                    variables.owner,
                    "dailyAuditions",
                    "weeklyAuditions",
                    "transfer"
                );
                expect( second.deduplicated ).toBe( 1 );
            } );
            it( "discards pending items without requiring transfer compatibility", () => {
                add();
                publish( "one" );
                variables.genericPolicy.setTransferAllowed( false );
                var result = variables.generic.transferSubscription(
                    variables.owner,
                    "dailyAuditions",
                    "weeklyAuditions",
                    "discard"
                );
                expect( result.suppressed ).toBe( 1 );
                expect( variables.digestStore.pending( result.destination.id ) ).toBeEmpty();
            } );
            it( "rejects incompatible transfers", () => {
                add();
                publish( "one" );
                variables.genericPolicy.setTransferAllowed( false );
                expect( () => variables.generic.transferSubscription(
                    variables.owner,
                    "dailyAuditions",
                    "weeklyAuditions",
                    "transfer"
                ) ).toThrow( "Megaphone.Digests.IncompatibleTransfer" );
            } );
            it( "does not transfer any membership from a partially sent batch", () => {
                add();
                publish( "one" );
                var batch = freezeGeneric();
                variables.generic.publishBatch( variables.owner, batch.id );
                variables.presentation.setChannels( [ "summaryEmail" ] );
                variables.generic.dispatchPublishedBatch( batch.id );
                var result = variables.generic.transferSubscription(
                    variables.owner,
                    "dailyAuditions",
                    "weeklyAuditions",
                    "transfer"
                );
                expect( result.nontransferable ).toBe( 1 );
                expect( result.transferred ).toBe( 0 );
            } );
            it( "requires explicit transfer disposition and distinct digest names", () => {
                expect( () => variables.generic.transferSubscription(
                    variables.owner,
                    "dailyAuditions",
                    "dailyAuditions",
                    "transfer"
                ) ).toThrow( "Megaphone.Digests.InvalidTransfer" );
                expect( () => variables.generic.transferSubscription(
                    variables.owner,
                    "dailyAuditions",
                    "weeklyAuditions",
                    "finish"
                ) ).toThrow( "Megaphone.Digests.InvalidTransfer" );
            } );
            it( "keeps stopped subscriptions stopped when updating their saved timezone", () => {
                add();
                variables.generic.stopSubscription( variables.owner, "dailyAuditions" );
                var updated = variables.generic.updateSubscription(
                    notifiable = variables.owner,
                    digestName = "dailyAuditions",
                    timezone = "UTC"
                );
                expect( updated.mode ).toBe( "off" );
                expect( updated.timezone ).toBe( "UTC" );
                expect( variables.generic.resumeSubscription( variables.owner, "dailyAuditions" ).timezone ).toBe( "UTC" );
            } );
            it( "creates one-item batches when transferring into an existing immediate subscription", () => {
                add();
                variables.generic.addSubscription(
                    notifiable = variables.owner,
                    digestName = "weeklyAuditions",
                    mode = "immediate",
                    clock = variables.start
                );
                publish( "one" );
                var result = variables.generic.transferSubscription(
                    variables.owner,
                    "dailyAuditions",
                    "weeklyAuditions",
                    "transfer"
                );
                expect( result.transferred ).toBe( 1 );
                var pending = variables.digestStore.pending( result.destination.id );
                expect( pending[ 1 ].state ).toBe( "batched" );
                variables.generic.dispatchDue();
                expect( variables.summaryEmail.getSent().len() ).toBe( 1 );
            } );
            it( "drops newly ineligible items during transfer", () => {
                add();
                publish( "one" );
                variables.genericPolicy.setExcluded( { "one": true } );
                var result = variables.generic.transferSubscription(
                    variables.owner,
                    "dailyAuditions",
                    "weeklyAuditions",
                    "transfer"
                );
                expect( result.suppressed ).toBe( 1 );
                expect( result.transferred ).toBe( 0 );
            } );
            it( "does not collect a saved source plan admitted after transfer", () => {
                add();
                var plan = variables.notifications.plan(
                    variables.owner,
                    new tests.resources.GenericDigestSourceFixture(),
                    entry( "late" ),
                    { "eventKey": createUUID() }
                );
                variables.generic.transferSubscription(
                    variables.owner,
                    "dailyAuditions",
                    "weeklyAuditions",
                    "transfer"
                );
                expect( variables.notifications.queuePlan( plan ).getCollections()[ 1 ].status ).toBe( "suppressed" );
            } );
            it( "moves unstarted frozen membership and suppresses the obsolete summary", () => {
                add();
                publish( "one" );
                var batch = freezeGeneric();
                variables.generic.publishBatch( variables.owner, batch.id );
                var result = variables.generic.transferSubscription(
                    variables.owner,
                    "dailyAuditions",
                    "weeklyAuditions",
                    "transfer"
                );
                expect( result.transferred ).toBe( 1 );
                variables.generic.dispatchPublishedBatch( batch.id );
                expect( variables.summaryEmail.getSent() ).toBeEmpty();
                expect( variables.summarySMS.getSent() ).toBeEmpty();
            } );
            it( "requires a transfer hook even when the ordinary destination policy permits collection", () => {
                add();
                publish( "one" );
                variables.config.digests.weeklyAuditions.policy = new tests.resources.DigestPolicyFixture();
                try {
                    expect( () => variables.generic.transferSubscription(
                        variables.owner,
                        "dailyAuditions",
                        "weeklyAuditions",
                        "transfer"
                    ) ).toThrow( "Megaphone.Digests.IncompatibleTransfer" );
                } finally {
                    variables.config.digests.weeklyAuditions.policy = variables.genericPolicy;
                }
            } );
            it( "rejects conflicting add settings and missing lifecycle identities", () => {
                add();
                expect( () => variables.generic.addSubscription(
                    notifiable = variables.owner,
                    digestName = "dailyAuditions",
                    timezone = "UTC"
                ) ).toThrow( "Megaphone.Digests.SubscriptionConflict" );
                expect( () => variables.generic.resumeSubscription( variables.owner, "weeklyAuditions" ) ).toThrow( "Megaphone.Digests.SubscriptionMissing" );
            } );
        } );
    }

    private struct function add( string digestName = "dailyAuditions" ) {
        return variables.generic.addSubscription(
            notifiable = variables.owner,
            digestName = arguments.digestName,
            timezone = "America/Denver",
            clock = variables.start
        );
    }

    private struct function entry( required string key, array channels = [ "dailyAuditions" ] ) {
        return {
            "itemKey": arguments.key,
            "occurredAt": variables.calendar.epoch( dateAdd( "h", 1, variables.start ) ),
            "data": { "auditionId": arguments.key },
            "channels": arguments.channels
        };
    }

    private any function publish( required string key, string eventKey = createUUID() ) {
        return variables.notifications.queue(
            variables.owner,
            new tests.resources.GenericDigestSourceFixture(),
            entry( arguments.key ),
            { "eventKey": arguments.eventKey }
        );
    }

    private struct function freezeGeneric( string digestName = "dailyAuditions" ) {
        return variables.generic.prepareDigest(
            arguments.digestName,
            variables.calendar.epoch( now() ),
            "America/Denver"
        )[ 1 ];
    }

}
