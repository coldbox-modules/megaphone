/** Committed fixtures let independent database connections exercise the actual row locks. */
component extends="tests.specs.integration.EmailDigestSpec" {

    function run() {
        describe( "Concurrent digest workers", () => {
            beforeEach( () => {
                variables.owner = new tests.resources.InboxRecipient();
                variables.calendar = new megaphone.models.Digests.EmailDigestSchedule();
                variables.start = dateAdd( "d", -10, now() );
                variables.subscription = variables.digests.setSubscription(
                    notifiable = variables.owner,
                    digestName = "discovery",
                    mode = "digest",
                    clock = variables.start
                );
                variables.policy
                    .setConsent( true )
                    .setAdmission( true )
                    .setExcluded( {} );
                variables.renderer.setRendered( [] ).setOnRender( javacast( "null", "" ) );
                variables.mail.setOutcome( "accepted" ).setSent( [] );
            } );
            afterEach( () => cleanup() );
            it( "admits one item under simultaneous duplicate publication", () => {
                var results = together( [
                    () => {
                        return admit( "same" );
                    },
                    () => {
                        return admit( "same" );
                    }
                ] );
                expect( results[ 1 ].id ).toBe( results[ 2 ].id );
                expect( results.filter( ( result ) => result.created ).len() ).toBe( 1 );
            } );
            it( "creates one immediate batch under simultaneous duplicate admission", () => {
                variables.digests.setSubscription(
                    notifiable = variables.owner,
                    digestName = "discovery",
                    mode = "immediate",
                    clock = variables.start
                );
                var results = together( [
                    () => {
                        return admit( "same-immediate" );
                    },
                    () => {
                        return admit( "same-immediate" );
                    }
                ] );
                expect( results[ 1 ].deliveryId ).toBe( results[ 2 ].deliveryId );
                expect( results.filter( ( result ) => result.created ).len() ).toBe( 1 );
                together( [
                    () => variables.operations.dispatch( results[ 1 ].deliveryId ),
                    () => variables.operations.dispatch( results[ 2 ].deliveryId )
                ] );
                expect( variables.mail.getSent().len() ).toBe( 1 );
            } );
            it( "freezes one batch under simultaneous scheduler pickup", () => {
                admit( "one" );
                var results = together( [
                    () => {
                        return freezeDue();
                    },
                    () => {
                        return freezeDue();
                    }
                ] );
                expect( results[ 1 ].len() + results[ 2 ].len() ).toBe( 1 );
                var batches = builder()
                    .from( "megaphone_digest_batches" )
                    .where( "subscriptionId", variables.subscription.id )
                    .get();
                expect( batches.len() ).toBe( 1 );
                expect( variables.digestStore.items( batches[ 1 ].id ).len() ).toBe( 1 );
            } );
            it( "permits one mail transport under simultaneous dispatch", () => {
                admit( "one" );
                var batch = freezeDue()[ 1 ];
                together( [
                    () => variables.operations.dispatch( batch.deliveryId ).getStatus(),
                    () => variables.operations.dispatch( batch.deliveryId ).getStatus()
                ] );
                expect( variables.mail.getSent().len() ).toBe( 1 );
                expect( variables.deliveries.find( batch.deliveryId ).state ).toBe( "accepted" );
                expect( variables.deliveries.find( batch.deliveryId ).transportCount ).toBe( 1 );
            } );
            it( "excludes a cutoff admission whichever worker acquires the subscription lock first", () => {
                admit( "before" );
                together( [
                    () => {
                        return freezeDue();
                    },
                    () => {
                        return admit( "at", variables.subscription.lastCutoffAt + 7 * 24 * 60 * 60 * 1000 );
                    }
                ] );
                var batches = builder()
                    .from( "megaphone_digest_batches" )
                    .where( "subscriptionId", variables.subscription.id )
                    .get();
                expect( variables.digestStore.items( batches[ 1 ].id ).map( ( row ) => row.itemKey ) ).toBe( [ "before" ] );
                var pending = builder()
                    .from( "megaphone_digest_items" )
                    .where( "subscriptionId", variables.subscription.id )
                    .where( "itemKey", "at" )
                    .first();
                expect( pending.state ).toBe( "collected" );
            } );
        } );
    }
    private struct function admit( required string key, numeric at ) {
        var instant = isNull( arguments.at ) ? variables.calendar.epoch( dateAdd( "h", 1, variables.start ) ) : arguments.at;
        return variables.digests.collect(
            notifiable = variables.owner,
            digestName = "discovery",
            itemKey = arguments.key,
            data = { "message": arguments.key },
            occurredAt = instant,
            clock = createObject( "java", "java.util.Date" ).init( javacast( "long", instant ) )
        );
    }
    private array function freezeDue() {
        return variables.digests.prepareDigest(
            "discovery",
            variables.subscription.lastCutoffAt + 7 * 24 * 60 * 60 * 1000,
            variables.subscription.timezone
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
    private void function cleanup() {
        var batches = builder()
            .from( "megaphone_digest_batches" )
            .where( "subscriptionId", variables.subscription.id )
            .get();
        for ( var batch in batches ) {
            if ( len( batch.deliveryId ?: "" ) ) {
                var work = variables.deliveries.find( batch.deliveryId );
                builder()
                    .from( "megaphone_delivery_attempts" )
                    .where( "deliveryId", batch.deliveryId )
                    .delete();
                builder()
                    .from( "megaphone_deliveries" )
                    .where( "id", batch.deliveryId )
                    .delete();
                builder()
                    .from( "megaphone_events" )
                    .where( "id", work.eventId )
                    .delete();
            }
        }
        builder()
            .from( "megaphone_digest_items" )
            .where( "subscriptionId", variables.subscription.id )
            .delete();
        builder()
            .from( "megaphone_digest_batches" )
            .where( "subscriptionId", variables.subscription.id )
            .delete();
        builder()
            .from( "megaphone_digest_subscriptions" )
            .where( "id", variables.subscription.id )
            .delete();
    }
    private any function builder() {
        return variables.injector.getInstance( "QueryBuilder@qb" );
    }

}
