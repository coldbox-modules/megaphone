/** Compare recordset admission against actual scalar JDBC writes, not JSON/compiler output alone. */
component extends="tests.specs.integration.DeliveryStoreSpec" {

    function run() {
        describe( "Stock PostgreSQL JSON admission", () => {
            aroundEach( ( spec ) => {
                transaction {
                    try {
                        spec.body();
                    } finally {
                        transactionRollback();
                    }
                }
            } );
            it( "matches scalar timestamp wall values across DB zones, DST boundaries and fractional instants", () => {
                var dates = [
                    "2026-03-08T06:59:59.123Z",
                    "2026-03-08T07:00:00.987Z",
                    "2026-11-01T05:30:00.456Z",
                    "2026-11-01T06:30:00.654Z"
                ];
                for ( var zone in [ "UTC", "America/New_York", "Pacific/Auckland" ] ) {
                    queryExecute(
                        "SELECT set_config('TimeZone', :zone, true)",
                        { "zone": { "value": zone, "cfsqltype": "varchar" } }
                    );
                    for ( var instant in dates ) {
                        var clock = createObject( "java", "java.util.Date" ).from(
                            createObject( "java", "java.time.Instant" ).parse( instant )
                        );
                        var input = {
                            "namespace": createUUID(),
                            "eventKey": "'quoted ? --",
                            "version": 1,
                            "type": "notice",
                            "payload": { "text": "literal '""? OR true -- ", "empty": "" },
                            "payloadHash": "000123",
                            "notificationMapping": "",
                            "createdDate": clock
                        };
                        var scalar = variables.events.record( argumentCollection = input );
                        input.namespace = createUUID();
                        var reference = variables.events.recordReferences( [ input ] )[ 1 ];
                        var stored = variables.events.find( reference.id );
                        expect( stored.payload ).toBe( scalar.payload );
                        expect( stored.payloadHash ).toBe( "000123" );
                        expect( stored.notificationMapping ?: "" ).toBe( "" );
                        expect( wall( "megaphone_events", reference.id, "createdDate" ) ).toBe(
                            wall( "megaphone_events", scalar.id, "createdDate" ),
                            zone & " / " & instant
                        );
                        var intent = {
                            "eventId": scalar.id,
                            "recipientType": "User",
                            "recipientId": "00001",
                            "channel": "email",
                            "deviceId": "",
                            "routingData": { "text": "' OR true -- ?", "empty": "" },
                            "routingHash": "000123",
                            "availableDate": clock
                        };
                        var normal = variables.deliveries.enqueue( argumentCollection = intent );
                        intent.eventId = reference.id;
                        var fast = variables.deliveries.enqueueReferences( [ intent ] )[ 1 ];
                        var work = variables.deliveries.find( fast.id );
                        expect( wall( "megaphone_deliveries", fast.id, "availableDate" ) ).toBe(
                            wall( "megaphone_deliveries", normal.id, "availableDate" ),
                            zone & " / " & instant
                        );
                        expect( work.recipientId ).toBe( "00001" );
                        expect( work.deviceId ).toBe( "" );
                        expect( work.routingHash ).toBe( "000123" );
                        expect( work.routingData ).toBe( intent.routingData );
                        expect( isDate( work.settledDate ?: "" ) ).toBeFalse();
                        intent.channel = "push";
                        intent.initialState = "suppressed";
                        var suppressed = variables.deliveries.enqueueReferences( [ intent ] )[ 1 ];
                        expect( isDate( variables.deliveries.find( suppressed.id ).settledDate ) ).toBeTrue();
                    }
                }
            } );
        } );
    }
    private string function wall( required string table, required string id, required string column ) {
        return variables.injector
            .getInstance( "QueryBuilder@qb" )
            .from( arguments.table )
            .selectRaw( "CAST(""" & arguments.column & """ AS TEXT) AS value" )
            .where( "id", arguments.id )
            .get()[ 1 ].value;
    }

}
