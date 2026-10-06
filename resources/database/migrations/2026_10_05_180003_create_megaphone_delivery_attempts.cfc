component {

    function up( schema ) {
        schema.create( "megaphone_delivery_attempts", ( table ) => {
            table.string( "id", 36 ).primaryKey();
            table.string( "deliveryId", 36 );
            table.integer( "number" );
            table.string( "leaseToken", 36 );
            table.string( "outcome", 30 );
            table.string( "providerReference", 190 ).default( "" );
            table.string( "reason", 190 ).default( "" );
            table.timestamp( "startedDate" );
            table.timestamp( "transportStartedDate" ).nullable();
            table.timestamp( "finishedDate" ).nullable();
            table
                .foreignKey( "deliveryId", "fk_megaphone_attempt_delivery" )
                .references( "id" )
                .onTable( "megaphone_deliveries" );
            table.unique( [ "deliveryId", "number" ], "uq_megaphone_delivery_attempt" );
            table.index( [ "finishedDate", "id" ], "idx_megaphone_attempt_retention" );
        } );
    }
    function down( schema ) {
        schema.dropIfExists( "megaphone_delivery_attempts" );
    }

}
