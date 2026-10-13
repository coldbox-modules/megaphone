component {

    function up( schema ) {
        updatePrecision( schema, 6 );
    }
    function down( schema ) {
        updatePrecision( schema, 0 );
    }
    private function updatePrecision( schema, precision ) {
        // MySQL rounds whole-second timestamps, which can defer immediately due work.
        if ( !isInstanceOf( schema.getGrammar(), "qb.models.Grammars.MySQLGrammar" ) ) {
            return;
        }
        schema.alter( "megaphone_deliveries", function( table ) {
            for ( var name in [ "availableDate", "createdDate", "updatedDate" ] ) {
                var column = table.timestamp( name, precision ).withCurrent( precision );
                table.modifyColumn( name, column );
            }
            for ( var name in [ "leaseUntil", "transportStartedDate", "settledDate" ] ) {
                table.modifyColumn( name, table.timestamp( name, precision ).nullable() );
            }
        } );
    }

}
