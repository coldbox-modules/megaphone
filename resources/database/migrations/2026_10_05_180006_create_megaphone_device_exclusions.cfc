component {

    function up( schema ) {
        schema.create( "megaphone_device_exclusions", ( table ) => {
            table.string( "recipientType", 80 );
            table.string( "recipientId", 100 );
            table.string( "notificationType", 160 );
            table.string( "deviceId", 36 );
            table.primaryKey(
                [
                    "recipientType",
                    "recipientId",
                    "notificationType",
                    "deviceId"
                ],
                "pk_megaphone_device_exclusion"
            );
            table
                .foreignKey( "deviceId", "fk_megaphone_exclusion_device" )
                .references( "id" )
                .onTable( "megaphone_subscriptions" );
        } );
    }
    function down( schema ) {
        schema.dropIfExists( "megaphone_device_exclusions" );
    }

}
