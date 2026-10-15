/** Real PostgreSQL admission through both QB9 fallback and QB14 RETURNING. */
component extends="tests.resources.BulkNotificationSpecBase" {

    function run() {
        describe( "Reference-only durable storage", () => {
            aroundEach( ( spec ) => {
                transaction {
                    try {
                        variables.owner = new tests.resources.InboxRecipient().setId( createUUID() );
                        variables.adapter = new tests.resources.BulkReferenceQueueFixture();
                        variables.config.queue.queueAdapter = variables.adapter;
                        variables.counter = {
                            "count": 0,
                            "sql": [],
                            "inserts": [],
                            "results": [],
                            "executions": 0
                        };
                        variables.originalInterceptor = variables.grammar.getInterceptorService();
                        variables.observer = new tests.resources.ReferenceQueryObserver()
                            .setDelegate( variables.originalInterceptor )
                            .setCounter( variables.counter );
                        variables.grammar.setInterceptorService( variables.observer );
                        // The positive control proves the observer receives the actual execution hook.
                        var probe = variables.injector.getInstance( "QueryBuilder@qb" );
                        probe
                            .from( "megaphone_events" )
                            .whereRaw( "1 = 0" )
                            .get();
                        variables.fast = new megaphone.models.Storage.BulkRecords().supportsReturning(
                            variables.injector.getInstance( "QueryBuilder@qb" )
                        );
                        spec.body();
                    } finally {
                        transactionRollback();
                        restoreStores();
                        variables.grammar.setInterceptorService( variables.originalInterceptor );
                    }
                }
            } );
            it( "uses the explicitly requested public QB14 PostgreSQL executor and keeps QB9 fallback", () => {
                expect( variables.fast ).toBe( application.megaphoneRequireReturning ?: false );
            } );
            it( "recognizes the exact stock source through mapping aliases while retaining real admission", () => {
                var bulk = new megaphone.models.Storage.BulkRecords();
                var queryAlias = new qbStockAlias.models.Query.QueryBuilder( grammar = variables.grammar );
                expect( getMetadata( queryAlias ).name ).notToBe(
                    getMetadata( variables.injector.getInstance( "QueryBuilder@qb" ) ).name
                );
                expect( bulk.supportsReturning( queryAlias ) ).toBe( variables.fast );
                var eventAlias = variables.injector.getInstance( "megaphoneStockAlias.models.Storage.EventStore" );
                var deliveryAlias = variables.injector.getInstance( "megaphoneStockAlias.models.Storage.DeliveryStore" );
                expect( bulk.isStockComponent( eventAlias, "megaphone.models.Storage.EventStore" ) ).toBeTrue();
                expect( bulk.isStockComponent( deliveryAlias, "megaphone.models.Storage.DeliveryStore" ) ).toBeTrue();
                var event = eventAlias.recordReferences( [ eventInput( createUUID() ) ] )[ 1 ];
                var work = deliveryAlias.enqueueReferences( [ deliveryInput( event.id ) ] )[ 1 ];
                expect( event.created ).toBeTrue();
                expect( work.created ).toBeTrue();
                expect( variables.counter.count == 0 ).toBe( variables.fast );
                expect( deliveryAlias.find( work.id ).eventId ).toBe( event.id );
            } );
            it( "returns minimal fresh references over a 1000-row boundary without identity readbacks on the fast path", () => {
                var total = variables.fast ? 1001 : 101;
                var inputs = [];
                for ( var index = 1; index <= total; index++ ) {
                    inputs.append( eventInput( createUUID() ) );
                }
                var eventReferences = variables.events.recordReferences( inputs );
                expect( variables.counter.count == 0 ).toBe(
                    variables.fast,
                    serializeJSON( {
                        "inserts": variables.counter.inserts,
                        "readbacks": variables.counter.count,
                        "results": variables.counter.results,
                        "store": getMetadata( variables.events ).name
                    } )
                );
                expect( eventReferences.len() ).toBe( total );
                if ( variables.fast ) {
                    expect( variables.counter.inserts.map( ( item ) => item.rows ) ).toBe( [ 1000, 1 ] );
                    expect( variables.counter.results.map( ( item ) => item.rows ) ).toBe( [ 1000, 1 ] );
                    expect( variables.counter.inserts.every( ( item ) => item.bindings <= 30000 ) ).toBeTrue();
                }
                for ( var event in eventReferences ) {
                    expect( event.keyArray().sort( "text" ) ).toBe( [ "created", "id" ] );
                    expect( event.created ).toBeTrue();
                }
                variables.counter.count = 0;
                variables.counter.sql = [];
                variables.counter.inserts = [];
                variables.counter.results = [];
                var intents = eventReferences.map( ( event ) => deliveryInput( event.id ) );
                var deliveryReferences = variables.deliveries.enqueueReferences( intents );
                expect( variables.counter.count == 0 ).toBe( variables.fast );
                expect( deliveryReferences.len() ).toBe( total );
                if ( variables.fast ) {
                    expect( variables.counter.inserts.map( ( item ) => item.rows ) ).toBe( [ 1000, 1 ] );
                    expect( variables.counter.results.map( ( item ) => item.rows ) ).toBe( [ 1000, 1 ] );
                    expect( variables.counter.inserts.every( ( item ) => item.bindings <= 30000 ) ).toBeTrue();
                }
                for ( var work in deliveryReferences ) {
                    expect( work.keyArray().sort( "text" ) ).toBe( [
                        "availableDate",
                        "created",
                        "id",
                        "state"
                    ] );
                    expect( work.created ).toBeTrue();
                    expect( work.state ).toBe( "queued" );
                    expect( dateDiff( "l", work.availableDate, intents[ 1 ].availableDate ) ).toBe( 0 );
                }
            } );
            it( "resolves duplicate and replayed identities across chunks while retaining conflicts and narrow reads", () => {
                var input = eventInput( createUUID() );
                var repeated = [];
                for ( var index = 1; index <= ( variables.fast ? 1001 : 101 ); index++ ) {
                    repeated.append( input );
                }
                var eventReferences = variables.events.recordReferences( repeated );
                expect( eventReferences.filter( ( row ) => row.created ).len() ).toBe( 1 );
                expect( eventReferences.every( ( row ) => row.id == eventReferences[ 1 ].id ) ).toBeTrue();
                if ( variables.fast ) {
                    expect( variables.counter.sql.len() ).toBeGT( 0 );
                    expect( variables.counter.sql.toList( " " ) ).notToInclude( """payload""" );
                }
                variables.counter.sql = [];
                var intent = deliveryInput( eventReferences[ 1 ].id );
                var intents = repeated.map( () => intent );
                var deliveryReferences = variables.deliveries.enqueueReferences( intents );
                expect( deliveryReferences.filter( ( row ) => row.created ).len() ).toBe( 1 );
                expect( deliveryReferences.every( ( row ) => row.id == deliveryReferences[ 1 ].id ) ).toBeTrue();
                if ( variables.fast ) {
                    expect( variables.counter.sql.toList( " " ) ).notToInclude( """routingData""" );
                }
                intent.routingHash = "conflict";
                expect( () => variables.deliveries.enqueueReferences( [ intent ] ) ).toThrow( "Megaphone.Delivery.IdentityConflict" );
                expect( isNull( variables.events.find( eventReferences[ 1 ].id ) ) ).toBeTrue();
            } );
            it( "rolls back earlier chunks on an immutable event conflict", () => {
                var input = eventInput( createUUID() );
                var first = variables.events.recordReferences( [ input ] )[ 1 ];
                var batch = [];
                for ( var index = 1; index <= 101; index++ ) {
                    batch.append( eventInput( createUUID() ) );
                }
                input.payloadHash = "changed";
                batch.append( input );
                expect( () => variables.events.recordReferences( batch ) ).toThrow( "Megaphone.Events.IdentityConflict" );
                expect( isNull( variables.events.find( first.id ) ) ).toBeTrue();
                expect(
                    variables.injector
                        .getInstance( "QueryBuilder@qb" )
                        .from( "megaphone_events" )
                        .count()
                ).toBe( 0 );
            } );
            it( "retains the generic insert and identity readback for a custom QueryBuilder subclass", () => {
                variables.injector
                    .getBinder()
                    .map( "QueryBuilder@qb", true )
                    .to( "tests.resources.CountingBulkQueryBuilder" )
                    .initArg( name = "grammar", value = variables.grammar )
                    .property( name = "compilationCounter", value = variables.counter );
                var query = variables.injector.getInstance( "QueryBuilder@qb" );
                expect( new megaphone.models.Storage.BulkRecords().supportsReturning( query ) ).toBeFalse();
                var reference = variables.events.recordReferences( [ eventInput( createUUID() ) ] )[ 1 ];
                expect( reference.created ).toBeTrue();
                expect( variables.counter.sql.len() ).toBeGT( 0 );
                expect( variables.events.find( reference.id ).payload.text ).toBe( "'quoted ?'" );
            } );
            it( "honors custom store overrides instead of bypassing their public batch methods", () => {
                var eventsCounter = { "count": 0 };
                var deliveryCounter = { "count": 0 };
                var eventReferences = variables.injector
                    .getInstance( "tests.resources.OverriddenReferenceEventStore" )
                    .setBatchCounter( eventsCounter );
                var deliveryReferences = variables.injector
                    .getInstance( "tests.resources.OverriddenReferenceDeliveryStore" )
                    .setBatchCounter( deliveryCounter );
                var event = eventReferences.recordReferences( [ eventInput( createUUID() ) ] )[ 1 ];
                var work = deliveryReferences.enqueueReferences( [ deliveryInput( event.id ) ] )[ 1 ];
                expect( eventsCounter.count ).toBe( 1 );
                expect( deliveryCounter.count ).toBe( 1 );
                expect( work.created ).toBeTrue();
            } );
            it( "keeps adapters that only implement the original batch store protocol", () => {
                var eventCounter = { "count": 0 };
                var deliveryCounter = { "count": 0 };
                variables.injector
                    .getBinder()
                    .map( "EventStore@megaphone" )
                    .toValue(
                        new tests.resources.LegacyBatchEventStore()
                            .setStore( variables.events )
                            .setBatchCounter( eventCounter )
                    );
                variables.injector
                    .getBinder()
                    .map( "DeliveryStore@megaphone" )
                    .toValue(
                        new tests.resources.LegacyBatchDeliveryStore()
                            .setStore( variables.deliveries )
                            .setBatchCounter( deliveryCounter )
                    );
                variables.service.admitRequests( [ notificationRequest( createUUID() ) ] );
                expect( eventCounter.count ).toBe( 1 );
                expect( deliveryCounter.count ).toBe( 1 );
                expect( variables.adapter.getReferences().len() ).toBe( 2 );
            } );
        } );
    }
    private struct function eventInput( required string key ) {
        return {
            "namespace": "references",
            "eventKey": arguments.key,
            "version": 1,
            "type": "notice",
            "payload": { "text": "'quoted ?'" },
            "payloadHash": "original"
        };
    }
    private struct function deliveryInput( required string id ) {
        return {
            "eventId": arguments.id,
            "recipientType": "User",
            "recipientId": "00012",
            "channel": "email",
            "deviceId": "",
            "routingData": { "text": "'quoted ?'" },
            "routingHash": "000123",
            "availableDate": dateAdd( "l", 123, createDateTime( 2026, 10, 15, 12, 13, 14 ) )
        };
    }
    private void function restoreStores() {
        variables.injector
            .getBinder()
            .map( "QueryBuilder@qb", true )
            .to( "qb.models.Query.QueryBuilder" )
            .initArg( name = "grammar", value = variables.grammar );
        variables.injector
            .getBinder()
            .map( "EventStore@megaphone" )
            .to( "megaphone.models.Storage.EventStore" );
        variables.injector
            .getBinder()
            .map( "DeliveryStore@megaphone" )
            .to( "megaphone.models.Storage.DeliveryStore" );
    }

}
