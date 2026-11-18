component extends="testbox.system.BaseSpec" {

    function run() {
        describe( "Restoring notification plan dates", () => {
            it( "preserves JDBC instants in event, delivery and cutoff dates", () => {
                var instant = createObject( "java", "java.time.Instant" ).parse( "2026-11-01T07:30:00.123Z" );
                var timestampType = createObject( "java", "java.sql.Timestamp" );
                var occurrence = timestampType.init( instant.toEpochMilli() );
                var later = timestampType.init( instant.plusSeconds( 3600 ).toEpochMilli() );
                var saved = {
                    "schemaVersion": 1,
                    "event": { "createdDate": occurrence },
                    "deliveries": [ { "availableDate": later } ],
                    "admitAfter": occurrence
                };
                // Exercise the production case where the request and JDBC display different wall times.
                var boxlangRuntime = structKeyExists( server, "boxlang" );
                if ( boxlangRuntime ) {
                    var originalZone = now().getZone().getId();
                    var jdbcOffset = createObject( "java", "java.util.TimeZone" )
                        .getDefault()
                        .getOffset( instant.toEpochMilli() );
                    setTimezone( jdbcOffset == 0 ? "America/Denver" : "UTC" );
                }
                try {
                    var restored = new megaphone.models.Delivery.NotificationPlan()
                        .populateFromMemento( saved )
                        .getMemento();
                } finally {
                    if ( boxlangRuntime ) {
                        setTimezone( originalZone );
                    }
                }
                expect( restored.event.createdDate.getTime() ).toBe( occurrence.getTime() );
                expect( restored.deliveries[ 1 ].availableDate.getTime() ).toBe( later.getTime() );
                expect( restored.admitAfter.getTime() ).toBe( occurrence.getTime() );
            } );
            it( "parses serialized dates with explicit offsets", () => {
                var saved = {
                    "schemaVersion": 1,
                    "event": { "createdDate": "2026-11-01T01:30:00-06:00" },
                    "deliveries": [ { "availableDate": "2026-11-01T01:30:00-07:00" } ],
                    "admitAfter": "2026-11-01T07:30:00Z"
                };
                var restored = new megaphone.models.Delivery.NotificationPlan()
                    .populateFromMemento( saved )
                    .getMemento();
                var instant = createObject( "java", "java.time.Instant" ).parse( "2026-11-01T07:30:00Z" );
                expect( restored.event.createdDate.getTime() ).toBe( instant.toEpochMilli() );
                expect( restored.deliveries[ 1 ].availableDate.getTime() ).toBe(
                    instant.plusSeconds( 3600 ).toEpochMilli()
                );
                expect( restored.admitAfter.getTime() ).toBe( instant.toEpochMilli() );
            } );
        } );
    }

}
