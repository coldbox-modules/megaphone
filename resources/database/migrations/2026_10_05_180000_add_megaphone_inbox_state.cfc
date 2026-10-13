component {

    function up( schema ) {
        schema.alter( "megaphone_notifications", ( table ) => {
            table.addColumn( table.timestamp( "archivedDate" ).nullable() );
            table.addColumn( table.string( "groupKey" ).nullable() );
            table.addIndex(
                name = "idx_megaphone_recipient_created",
                columns = [
                    "notifiableType",
                    "notifiableId",
                    "createdDate",
                    "id"
                ]
            );
            table.addIndex(
                name = "idx_megaphone_recipient_group",
                columns = [ "notifiableType", "notifiableId", "groupKey" ]
            );
        } );
    }

    function down( schema ) {
        schema.alter( "megaphone_notifications", ( table ) => {
            table.dropIndex( "idx_megaphone_recipient_created" );
            table.dropIndex( "idx_megaphone_recipient_group" );
            table.dropColumn( "archivedDate" );
            table.dropColumn( "groupKey" );
        } );
    }

}
