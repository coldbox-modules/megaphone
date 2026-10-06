component {

    function up( schema ) {
        schema.create( "megaphone_preferences", ( table ) => {
            table.string( "recipientType", 80 );
            table.string( "recipientId", 100 );
            table.string( "scopeKey", 100 );
            table.string( "notificationType", 160 );
            table.string( "channel", 60 );
            table.string( "choice", 3 );
            table.timestamp( "updatedDate" ).withCurrent();
            table.primaryKey(
                [
                    "recipientType",
                    "recipientId",
                    "scopeKey",
                    "notificationType",
                    "channel"
                ],
                "pk_megaphone_preference"
            );
        } );
    }
    function down( schema ) {
        schema.dropIfExists( "megaphone_preferences" );
    }

}
