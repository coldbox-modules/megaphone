/** Committed fixtures exercise independent connections, publication and preference locks. */
component extends="tests.specs.integration.GenericDigestSpec" {

    function run() {
        describe( "Concurrent generic digest lifecycle", () => {
            beforeEach( () => {
                variables.owner = new tests.resources.InboxRecipient();
                variables.calendar = new megaphone.models.Digests.EmailDigestSchedule();
                variables.start = dateAdd( "d", -10, now() );
                variables.genericPolicy
                    .setConsent( true )
                    .setAdmission( true )
                    .setExcluded( {} )
                    .setTransferAllowed( true );
                variables.presentation
                    .setChannels( [ "summaryEmail", "summarySMS" ] )
                    .setOnFormat( javacast( "null", "" ) );
                for ( var name in [ "dailyAuditions", "weeklyAuditions" ] ) {
                    variables.generic.addSubscription(
                        notifiable = variables.owner,
                        digestName = name,
                        timezone = "America/Denver",
                        clock = variables.start
                    );
                }
            } );
            afterEach( () => cleanupGeneric() );
            it( "retries local summary publication failures without marking provider acceptance uncertain", () => {
                admitGeneric( "one" );
                var batch = variables.generic.prepareDigest(
                    "dailyAuditions",
                    variables.calendar.epoch( now() ),
                    "America/Denver"
                )[ 1 ];
                variables.config.digests.dailyAuditions.notification = "MissingAuditionSummaryMapping";
                try {
                    expect( variables.operations.dispatch( batch.deliveryId ).getStatus() ).toBe( "retryable" );
                    expect( variables.deliveries.find( batch.deliveryId ).state ).toBe( "retryable" );
                } finally {
                    variables.config.digests.dailyAuditions.notification = "DailyAuditionsNotification";
                }
            } );
            it( "publishes one audience under simultaneous publication", () => {
                admitGeneric( "one" );
                var batch = variables.generic.prepareDigest(
                    "dailyAuditions",
                    variables.calendar.epoch( now() ),
                    "America/Denver"
                )[ 1 ];
                var results = together( [
                    () => variables.generic.publishBatch( variables.owner, batch.id ),
                    () => variables.generic.publishBatch( variables.owner, batch.id )
                ] );
                expect( results[ 1 ].eventId ).toBe( results[ 2 ].eventId );
                expect( variables.operations.getDeliveriesForEvent( results[ 1 ].eventId ).len() ).toBe( 2 );
            } );
            it( "transfers each item once under simultaneous preference changes", () => {
                admitGeneric( "one" );
                var results = together( [
                    () => variables.generic.transferSubscription(
                        variables.owner,
                        "dailyAuditions",
                        "weeklyAuditions",
                        "transfer"
                    ),
                    () => variables.generic.transferSubscription(
                        variables.owner,
                        "dailyAuditions",
                        "weeklyAuditions",
                        "transfer"
                    )
                ] );
                expect( results[ 1 ].transferred + results[ 2 ].transferred ).toBe( 1 );
                var destination = variables.generic.getSubscription( variables.owner, "weeklyAuditions" );
                expect( variables.digestStore.pending( destination.id ).len() ).toBe( 1 );
            } );
            it( "rolls back source changes after format rejection", () => {
                admitGeneric( "one" );
                variables.genericPolicy.setTransferAllowed( false );
                expect( () => variables.generic.transferSubscription(
                    variables.owner,
                    "dailyAuditions",
                    "weeklyAuditions",
                    "transfer"
                ) ).toThrow( "Megaphone.Digests.IncompatibleTransfer" );
                var source = variables.generic.getSubscription( variables.owner, "dailyAuditions" );
                expect( source.mode ).toBe( "digest" );
                expect( variables.digestStore.pending( source.id ).len() ).toBe( 1 );
            } );
            it( "serializes collection against a preference transfer", () => {
                admitGeneric( "one" );
                together( [
                    () => variables.generic.transferSubscription(
                        variables.owner,
                        "dailyAuditions",
                        "weeklyAuditions",
                        "transfer"
                    ),
                    () => admitGeneric( "two" )
                ] );
                var source = variables.generic.getSubscription( variables.owner, "dailyAuditions" );
                var destination = variables.generic.getSubscription( variables.owner, "weeklyAuditions" );
                expect( source.mode ).toBe( "off" );
                expect( variables.digestStore.pending( source.id ) ).toBeEmpty();
                expect(
                    variables.digestStore
                        .pending( destination.id )
                        .filter( ( item ) => item.itemKey == "one" )
                        .len()
                ).toBe( 1 );
            } );
            it( "uses one lock order for simultaneous opposite transfers", () => {
                admitGeneric( "one" );
                variables.generic.collect(
                    notifiable = variables.owner,
                    digestName = "weeklyAuditions",
                    itemKey = "two",
                    data = { "auditionId": "two" },
                    occurredAt = variables.calendar.epoch( now() )
                );
                together( [
                    () => variables.generic.transferSubscription(
                        variables.owner,
                        "dailyAuditions",
                        "weeklyAuditions",
                        "transfer"
                    ),
                    () => variables.generic.transferSubscription(
                        variables.owner,
                        "weeklyAuditions",
                        "dailyAuditions",
                        "transfer"
                    )
                ] );
                var daily = variables.generic.getSubscription( variables.owner, "dailyAuditions" );
                var weekly = variables.generic.getSubscription( variables.owner, "weeklyAuditions" );
                expect( ( daily.mode == "digest" ? 1 : 0 ) + ( weekly.mode == "digest" ? 1 : 0 ) ).toBe( 1 );
                expect(
                    variables.digestStore.pending( daily.id ).len() + variables.digestStore.pending( weekly.id ).len()
                ).toBe( 2 );
            } );
            it( "preserves unsent content through daily to weekly to daily transfers", () => {
                admitGeneric( "one" );
                variables.generic.transferSubscription(
                    variables.owner,
                    "dailyAuditions",
                    "weeklyAuditions",
                    "transfer"
                );
                variables.generic.transferSubscription(
                    variables.owner,
                    "weeklyAuditions",
                    "dailyAuditions",
                    "transfer"
                );
                var source = variables.generic.getSubscription( variables.owner, "dailyAuditions" );
                expect( variables.digestStore.pending( source.id ).map( ( item ) => item.itemKey ) ).toBe( [ "one" ] );
            } );
            it( "fails a conflicting transfer atomically without stopping the source", () => {
                admitGeneric( "one" );
                variables.generic.collect(
                    notifiable = variables.owner,
                    digestName = "weeklyAuditions",
                    itemKey = "one",
                    data = { "auditionId": "different" },
                    occurredAt = variables.calendar.epoch( now() )
                );
                expect( () => variables.generic.transferSubscription(
                    variables.owner,
                    "dailyAuditions",
                    "weeklyAuditions",
                    "transfer"
                ) ).toThrow( "Megaphone.Digests.IdentityConflict" );
                var source = variables.generic.getSubscription( variables.owner, "dailyAuditions" );
                expect( source.mode ).toBe( "digest" );
                expect( variables.digestStore.pending( source.id ).len() ).toBe( 1 );
            } );
        } );
    }

    private any function admitGeneric( required string key ) {
        return variables.generic.collect(
            notifiable = variables.owner,
            digestName = "dailyAuditions",
            itemKey = arguments.key,
            data = { "auditionId": arguments.key },
            occurredAt = variables.calendar.epoch( now() )
        );
    }

    private array function together( required array work ) {
        var names = [];
        var outcomes = [];
        var ready = createObject( "java", "java.util.concurrent.CountDownLatch" ).init(
            javacast( "int", arguments.work.len() )
        );
        var start = createObject( "java", "java.util.concurrent.CountDownLatch" ).init( javacast( "int", 1 ) );
        var seconds = createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS;
        for ( var task in arguments.work ) {
            var workerName = "digest" & replace( createUUID(), "-", "", "all" );
            var outcome = createObject( "java", "java.util.concurrent.CompletableFuture" ).init();
            outcomes.append( outcome );
            names.append( workerName );
            thread name=workerName action="run" callback=task ready=ready start=start seconds=seconds outcome=outcome {
                attributes.ready.countDown();
                try {
                    if ( !attributes.start.await( javacast( "long", 10 ), attributes.seconds ) ) {
                        throw( message = "Worker start timed out." );
                    }
                    var callback = attributes.callback;
                    attributes.outcome.complete( { "result": callback() } );
                } catch ( any error ) {
                    attributes.outcome.complete( { "problem": error.message & " " & error.detail } );
                }
            }
        }
        var allReady = ready.await( javacast( "long", 10 ), seconds );
        start.countDown();
        thread action="join" name=names.toList() timeout=15000;
        expect( allReady ).toBeTrue();
        var results = [];
        for ( var index = 1; index <= names.len(); index++ ) {
            expect( cfthread[ names[ index ] ].status ).toBe( "COMPLETED" );
            var answer = outcomes[ index ].get( javacast( "long", 1 ), seconds );
            if ( !structKeyExists( answer, "result" ) ) {
                throw( message = "Digest worker did not return a result: " & serializeJSON( answer ) );
            }
            results.append( answer.result );
        }
        return results;
    }

    private void function cleanupGeneric() {
        var recipientId = variables.owner.getNotifiableId();
        recipientId = isValid( "uuid", recipientId ) ? lCase( recipientId ) : recipientId;
        var subscriptions = builder()
            .from( "megaphone_digest_subscriptions" )
            .where( "notifiableId", recipientId )
            .get();
        for ( var subscription in subscriptions ) {
            for (
                var batch in builder()
                    .from( "megaphone_digest_batches" )
                    .where( "subscriptionId", subscription.id )
                    .get()
            ) {
                var eventIds = [];
                if ( len( batch.deliveryId ?: "" ) ) {
                    eventIds.append( variables.deliveries.find( batch.deliveryId ).eventId );
                }
                var publication = variables.digestStore.publication( batch.id );
                if ( !isNull( publication ) && len( publication.eventId ?: "" ) ) {
                    eventIds.append( publication.eventId );
                }
                for ( var eventId in eventIds ) {
                    for ( var work in variables.deliveries.forEvent( eventId ) ) {
                        builder()
                            .from( "megaphone_delivery_attempts" )
                            .where( "deliveryId", work.id )
                            .delete();
                    }
                    builder()
                        .from( "megaphone_deliveries" )
                        .where( "eventId", eventId )
                        .delete();
                }
                builder()
                    .from( "megaphone_digest_publications" )
                    .where( "batchId", batch.id )
                    .delete();
                if ( !eventIds.isEmpty() ) {
                    builder()
                        .from( "megaphone_events" )
                        .whereIn( "id", eventIds )
                        .delete();
                }
            }
            var itemIds = builder()
                .from( "megaphone_digest_items" )
                .where( "subscriptionId", subscription.id )
                .get()
                .map( ( item ) => item.id );
            if ( !itemIds.isEmpty() ) {
                builder()
                    .from( "megaphone_digest_admissions" )
                    .whereIn( "itemId", itemIds )
                    .delete();
            }
            builder()
                .from( "megaphone_digest_items" )
                .where( "subscriptionId", subscription.id )
                .delete();
            builder()
                .from( "megaphone_digest_batches" )
                .where( "subscriptionId", subscription.id )
                .delete();
            builder()
                .from( "megaphone_digest_subscriptions" )
                .where( "id", subscription.id )
                .delete();
        }
    }

    private any function builder() {
        return variables.injector.getInstance( "QueryBuilder@qb" );
    }

}
