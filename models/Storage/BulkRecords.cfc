/** Bounded identity reads retain database collation and caller order without per-row queries. */
component {

    public array function read( required any queryFactory, required array identities, required string tableName ) {
        var result = [];
        for ( var offset = 1; offset <= arguments.identities.len(); offset += 100 ) {
            var size = min( 100, arguments.identities.len() - offset + 1 );
            // A builder per identity makes UNION snapshots copy thousands of injected objects.
            // Compile each branch with one builder, retaining grammar-generated SQL and bindings.
            var query = arguments.queryFactory();
            var branches = [];
            var bindings = [];
            var wrapping = {};
            if ( isCustomFunction( query.getShouldWrapValues ?: "" ) ) {
                var configuredWrapping = query.getShouldWrapValues();
                if ( !isNull( configuredWrapping ) ) {
                    wrapping.value = configuredWrapping;
                }
            }
            for ( var index = 1; index <= size; index++ ) {
                var identity = arguments.identities[ offset + index - 1 ];
                query.reset().from( arguments.tableName );
                restoreWrapping( query, wrapping );
                query.selectRaw( "*, ? AS megaphoneBulkOrdinal", [ { "value": index, "cfsqltype": "integer" } ] );
                for ( var key in identity ) {
                    if ( isArray( identity[ key ] ) ) {
                        query.whereIn( key, identity[ key ] );
                    } else {
                        query.where( key, identity[ key ] );
                    }
                }
                branches.append( query.toSQL() );
                bindings.append( query.getBindings(), true );
                result.append( [] );
            }
            query.reset();
            restoreWrapping( query, wrapping );
            // All values remain bound parameters; table/column syntax came from the configured grammar.
            query.fromRaw( "(" & branches.toList( " UNION ALL " ) & ") megaphone_bulk_records", bindings );
            for ( var row in query.get() ) {
                var ordinal = val( row.megaphoneBulkOrdinal );
                structDelete( row, "megaphoneBulkOrdinal" );
                result[ offset + ordinal - 1 ].append( row );
            }
        }
        return result;
    }

    private void function restoreWrapping( required any query, required struct wrapping ) {
        if ( structKeyExists( arguments.wrapping, "value" ) ) {
            if ( arguments.wrapping.value ) {
                arguments.query.withWrappingValues();
            } else {
                arguments.query.withoutWrappingValues();
            }
        }
    }

    /** Keep wide inserts below conservative driver bind limits as well as 100 rows. */
    public numeric function insertSize( required struct row ) {
        return max( 1, min( 100, int( 900 / structCount( arguments.row ) ) ) );
    }

}
