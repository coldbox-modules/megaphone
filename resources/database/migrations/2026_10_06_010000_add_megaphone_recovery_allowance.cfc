component {

    function up( schema ) {
        schema.alter( "megaphone_deliveries", ( table ) => table.integer( "recoveryAllowance" ).default( 0 ) );
    }
    function down( schema ) {
        schema.alter( "megaphone_deliveries", ( table ) => table.dropColumn( "recoveryAllowance" ) );
    }

}
