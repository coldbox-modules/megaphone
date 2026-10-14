component {

    function up( schema ) {
        schema.create( "megaphone_digest_subscriptions", ( table ) => {
            table.string( "id", 36 ).primaryKey();
            table.string( "digestName", 100 );
            table.string( "notifiableType", 100 );
            table.string( "notifiableId", 190 );
            table.string( "mode", 20 );
            table.integer( "generation" );
            table.string( "timezone", 100 );
            table.longText( "schedule" );
            table.bigInteger( "effectiveAt" );
            table.bigInteger( "lastCutoffAt" );
            table.unique( [ "digestName", "notifiableType", "notifiableId" ], "uq_megaphone_digest_subscription" );
            table.index( [ "mode", "lastCutoffAt" ], "idx_megaphone_digest_due" );
        } );
        schema.create( "megaphone_digest_batches", ( table ) => {
            table.string( "id", 36 ).primaryKey();
            table.string( "subscriptionId", 36 );
            table.integer( "generation" );
            table.bigInteger( "cutoffAt" );
            table.string( "mode", 20 );
            table.string( "batchKey", 190 );
            table.string( "state", 20 );
            table.string( "deliveryId", 36 ).nullable();
            table.unique( [ "subscriptionId", "generation", "batchKey" ], "uq_megaphone_digest_batch" );
            table
                .foreignKey( "subscriptionId", "fk_megaphone_digest_batch_subscription" )
                .references( "id" )
                .onTable( "megaphone_digest_subscriptions" );
        } );
        schema.create( "megaphone_digest_items", ( table ) => {
            table.string( "id", 36 ).primaryKey();
            table.string( "subscriptionId", 36 );
            table.integer( "generation" );
            table.string( "itemKey", 190 );
            table.string( "payloadHash", 128 );
            table.longText( "data" );
            table.bigInteger( "occurredAt" );
            table.bigInteger( "collectedAt" );
            table.string( "state", 20 );
            table.string( "eventId", 36 ).nullable();
            table.string( "batchId", 36 ).nullable();
            table.integer( "batchPosition" ).nullable();
            // Identity survives changes of mode, generation and collection retention.
            table.unique( [ "subscriptionId", "itemKey" ], "uq_megaphone_digest_item" );
            table.index(
                [
                    "subscriptionId",
                    "generation",
                    "state",
                    "collectedAt"
                ],
                "idx_megaphone_digest_collection"
            );
            table
                .foreignKey( "subscriptionId", "fk_megaphone_digest_item_subscription" )
                .references( "id" )
                .onTable( "megaphone_digest_subscriptions" );
            table
                .foreignKey( "batchId", "fk_megaphone_digest_item_batch" )
                .references( "id" )
                .onTable( "megaphone_digest_batches" );
        } );
        schema.create( "megaphone_digest_admissions", ( table ) => {
            table.string( "eventId", 36 );
            table.string( "itemId", 36 );
            table.unique( [ "eventId", "itemId" ], "uq_megaphone_digest_admission" );
            table
                .foreignKey( "itemId", "fk_megaphone_digest_admission_item" )
                .references( "id" )
                .onTable( "megaphone_digest_items" );
        } );
    }
    function down( schema ) {
        schema.dropIfExists( "megaphone_digest_admissions" );
        schema.dropIfExists( "megaphone_digest_items" );
        schema.dropIfExists( "megaphone_digest_batches" );
        schema.dropIfExists( "megaphone_digest_subscriptions" );
    }

}
