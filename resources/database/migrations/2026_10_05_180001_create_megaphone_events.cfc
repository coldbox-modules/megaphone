component {

    function up( schema ) {
        schema.create( "megaphone_events", ( table ) => {
            table.string( "id", 36 ).primaryKey();
            table.string( "namespace", 100 );
            table.string( "eventKey", 190 );
            table.integer( "version" );
            table.string( "type", 190 );
            table.string( "payloadHash", 128 );
            table.longText( "payload" );
            table.timestamp( "createdDate" ).withCurrent();
            table.unique( [ "namespace", "eventKey", "version" ], "uq_megaphone_event_identity" );
        } );
    }
    function down( schema ) {
        schema.dropIfExists( "megaphone_events" );
    }

}
