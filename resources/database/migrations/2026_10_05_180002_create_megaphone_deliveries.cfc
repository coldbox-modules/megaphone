component {

    function up( schema ) {
        schema.create( "megaphone_deliveries", ( table ) => {
            table.string( "id", 36 ).primaryKey();
            table.string( "eventId", 36 );
            table.string( "recipientType", 100 );
            table.string( "recipientId", 190 );
            table.string( "channel", 100 );
            table.string( "deviceId", 100 ).default( "" );
            table.string( "routingHash", 128 );
            table.longText( "routingData" );
            table.string( "state", 30 );
            table.integer( "attemptCount" ).default( 0 );
            table.integer( "transportCount" ).default( 0 );
            table.string( "leaseToken", 36 ).nullable();
            table.timestamp( "leaseUntil" ).nullable();
            table.timestamp( "transportStartedDate" ).nullable();
            table.timestamp( "availableDate" );
            table.timestamp( "createdDate" ).withCurrent();
            table.timestamp( "updatedDate" ).withCurrent();
            table.timestamp( "settledDate" ).nullable();
            table.string( "reason", 190 ).default( "" );
            table.string( "providerReference", 190 ).default( "" );
            table
                .foreignKey( "eventId", "fk_megaphone_delivery_event" )
                .references( "id" )
                .onTable( "megaphone_events" );
            table.unique(
                [
                    "eventId",
                    "recipientType",
                    "recipientId",
                    "channel",
                    "deviceId"
                ],
                "uq_megaphone_delivery_identity"
            );
            table.index( [ "state", "availableDate", "id" ], "idx_megaphone_delivery_due" );
            table.index( [ "state", "leaseUntil" ], "idx_megaphone_delivery_lease" );
            table.index( [ "settledDate", "id" ], "idx_megaphone_delivery_retention" );
        } );
    }
    function down( schema ) {
        schema.dropIfExists( "megaphone_deliveries" );
    }

}
