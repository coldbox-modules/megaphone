/** Additive to the 1.2.0 digest schema. Apply equivalent changes to configured custom tables. */
component {

    function up( schema ) {
        schema.alter( "megaphone_digest_subscriptions", ( table ) => {
            table.addColumn( table.string( "resumeMode", 20 ).default( "digest" ) );
        } );
        schema.create( "megaphone_digest_publications", ( table ) => {
            table.string( "batchId", 36 ).primaryKey();
            table
                .string( "eventId", 36 )
                .nullable()
                .unique();
            table.boolean( "transportStarted" ).default( false );
            table
                .foreignKey( "batchId", "fk_megaphone_digest_publication_batch" )
                .references( "id" )
                .onTable( "megaphone_digest_batches" );
        } );
    }

    function down( schema ) {
        schema.dropIfExists( "megaphone_digest_publications" );
        schema.alter( "megaphone_digest_subscriptions", ( table ) => {
            table.dropColumn( "resumeMode" );
        } );
    }

}
