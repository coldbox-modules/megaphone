component {

    function up( schema ) {
        schema.create( "megaphone_delivery_recoveries", ( table ) => {
            table.string( "id", 36 ).primaryKey();
            table.string( "deliveryId", 36 );
            table.string( "requestKey", 128 );
            table.string( "intentHash", 128 );
            table.string( "actorId", 190 );
            table.string( "actorLabel", 190 ).default( "" );
            table.string( "priorState", 30 );
            table.integer( "priorAttemptCount" );
            table.integer( "priorTransportCount" );
            table.string( "priorReason", 190 ).default( "" );
            table.string( "priorProviderReference", 190 ).default( "" );
            table.integer( "additionalAttempts" );
            table.timestamp( "createdDate" );
            table
                .foreignKey( "deliveryId", "fk_megaphone_recovery_delivery" )
                .references( "id" )
                .onTable( "megaphone_deliveries" );
            table.unique( [ "deliveryId", "requestKey" ], "uq_megaphone_recovery_request" );
            table.index( [ "deliveryId", "createdDate", "id" ], "idx_megaphone_recovery_history" );
        } );
    }
    function down( schema ) {
        schema.dropIfExists( "megaphone_delivery_recoveries" );
    }

}
