component {

    function up( schema ) {
        schema.alter( "megaphone_deliveries", ( table ) => {
            table.addColumn( table.integer( "recoveryAllowance" ).default( 0 ) );
        } );
    }

    function down( schema ) {
        // The original recovery migration owns removal of this column on rollback.
        // Retain it at this boundary so that migration's down remains executable.
    }

}
