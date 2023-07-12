component {

    function up( schema ) {
        schema.create( "megaphone_notifications", ( t ) => {
            t.guid( "id" ).primaryKey();
            t.string( "type" );
            t.string( "notifiableId" );
            t.string( "notifiableType" );
            t.longText( "data" );
            t.timestamp( "readDate" ).nullable();
            t.timestamp( "createdDate" ).withCurrent();

            t.index( "type" );
            t.index( "readDate" );
            t.index(
                name = "idx_megaphone_notifications_notifiable_index",
                columns = [ "notifiableId", "notifiableType" ]
            );
        } );
    }

    function down( schema ) {
        schema.dropIfExists( "megaphone_notifications" );
    }

}
