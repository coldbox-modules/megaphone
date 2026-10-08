component {

    function up( schema ) {
        schema.create( "megaphone_subscriptions", ( table ) => {
            table.string( "id", 36 ).primaryKey();
            table.string( "recipientType", 80 );
            table.string( "recipientId", 100 );
            table.string( "endpointHash", 64 );
            table
                .string( "endpointKey", 64 )
                .nullable()
                .unique();
            table.longText( "sealedData" );
            table.string( "label", 100 );
            table.boolean( "active" ).default( true );
            table.timestamp( "createdDate" ).withCurrent();
            table.timestamp( "renewedDate" ).withCurrent();
            table.timestamp( "expiresDate" ).nullable();
            table.timestamp( "retiredDate" ).nullable();
            table.index( [ "recipientType", "recipientId", "active" ], "idx_megaphone_subscription_owner" );
            table.index( [ "retiredDate", "id" ], "idx_megaphone_subscription_retention" );
        } );
    }
    function down( schema ) {
        schema.dropIfExists( "megaphone_subscriptions" );
    }

}
