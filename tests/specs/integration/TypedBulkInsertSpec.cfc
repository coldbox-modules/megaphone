component extends="tests.specs.integration.DeliveryStoreSpec" {

    function run() {
        describe( "Typed durable insert batches", () => {
            aroundEach( ( spec ) => {
                transaction {
                    try {
                        variables.counter = { "count": 0 };
                        var utils = new tests.resources.CountingBulkQueryUtils().setInferenceCounter(
                            variables.counter
                        );
                        variables.injector
                            .getBinder()
                            .map( "QueryBuilder@qb" )
                            .to( "qb.models.Query.QueryBuilder" )
                            .initArg( name = "grammar", value = variables.grammar )
                            .initArg( name = "utils", value = utils );
                        spec.body();
                    } finally {
                        transactionRollback();
                    }
                }
            } );
            it( "inserts 101 events and deliveries without SQL type inference or changing storage values", () => {
                var time = dateAdd( "l", 123, createDateTime( 2026, 10, 15, 12, 13, 14 ) );
                var namespace = createUUID();
                var inputs = [];
                for ( var index = 1; index <= 101; index++ ) {
                    inputs.append( {
                        "namespace": namespace,
                        "eventKey": "quote-'? OR true --" & index,
                        "version": index,
                        "type": "notice",
                        "payload": { "index": index, "message": "'quoted ?'" },
                        "payloadHash": "hash-" & index,
                        "createdDate": time,
                        "notificationMapping": index % 2 ? "" : "tests.resources.QueueNotification"
                    } );
                }
                // Compare persisted precision with the scalar path: MySQL event timestamps store whole seconds.
                var scalarInput = duplicate( inputs[ 1 ] );
                scalarInput.namespace = createUUID();
                var expectedDate = variables.events.record( argumentCollection = scalarInput ).createdDate;
                if ( variables.isPostgres ) {
                    expect( millisecondsBetween( expectedDate, time ) ).toBe( 0 );
                }
                variables.counter.count = 0;
                var events = variables.events.recordMany( inputs );
                var intents = [];
                for ( var event in events ) {
                    intents.append( {
                        "eventId": event.id,
                        "recipientType": "User",
                        "recipientId": "00012",
                        "channel": "email",
                        "deviceId": "",
                        "routingData": { "literal": "? ' OR true --" },
                        "routingHash": "000123",
                        "initialState": event.version % 2 ? "queued" : "suppressed",
                        "availableDate": time
                    } );
                }
                var deliveries = variables.deliveries.enqueueMany( intents );
                expect( variables.counter.count ).toBe( 0 );
                expect( events.len() ).toBe( 101 );
                expect( deliveries.len() ).toBe( 101 );
                for ( var index = 1; index <= 101; index++ ) {
                    var event = events[ index ];
                    var work = deliveries[ index ];
                    expect( event.eventKey ).toBe( inputs[ index ].eventKey );
                    expect( event.payload ).toBe( inputs[ index ].payload );
                    expect( millisecondsBetween( event.createdDate, expectedDate ) ).toBe( 0 );
                    expect( event.version ).toBe( index );
                    expect( work.deviceId ).toBe( "" );
                    expect( work.recipientId ).toBe( "00012" );
                    expect( work.routingHash ).toBe( "000123" );
                    expect( work.routingData ).toBe( intents[ index ].routingData );
                    expect( millisecondsBetween( work.availableDate, time ) ).toBe( 0 );
                    expect( work.attemptCount ).toBe( 0 );
                    expect( work.state ).toBe( intents[ index ].initialState );
                    expect( isDate( work.settledDate ?: "" ) ).toBe( work.state == "suppressed" );
                    expect( event.notificationMapping ?: "" ).toBe( inputs[ index ].notificationMapping );
                }
                var eventIds = events.map( ( item ) => {
                    return {
                        "value": item.id,
                        "cfsqltype": "varchar",
                        "null": false,
                        "list": false
                    };
                } );
                var deliveryIds = deliveries.map( ( item ) => {
                    return {
                        "value": item.id,
                        "cfsqltype": "varchar",
                        "null": false,
                        "list": false
                    };
                } );
                expect(
                    variables.injector
                        .getInstance( "QueryBuilder@qb" )
                        .from( "megaphone_events" )
                        .whereIn( "id", eventIds )
                        .whereNull( "notificationMapping" )
                        .count()
                ).toBe( 51 );
                expect(
                    variables.injector
                        .getInstance( "QueryBuilder@qb" )
                        .from( "megaphone_deliveries" )
                        .whereIn( "id", deliveryIds )
                        .whereNull( "settledDate" )
                        .count()
                ).toBe( 51 );
                expect( variables.events.recordMany( inputs ).map( ( item ) => item.created ) ).toBe(
                    inputs.map( () => false )
                );
                expect( variables.deliveries.enqueueMany( intents ).map( ( item ) => item.created ) ).toBe(
                    intents.map( () => false )
                );
                expect( variables.counter.count ).toBe( 0 );
            } );
        } );
    }

    private numeric function millisecondsBetween( required date start, required date finish ) {
        return parseDateTime( arguments.finish ).getTime() - parseDateTime( arguments.start ).getTime();
    }

}
