component {

    function up( schema ) {
        schema.alter( "megaphone_events", ( table ) => table.addColumn( table.string( "notificationMapping", 255 ).nullable() ) );
    }
    function down( schema ) {
        schema.alter( "megaphone_events", ( table ) => table.dropColumn( "notificationMapping" ) );
    }

}
