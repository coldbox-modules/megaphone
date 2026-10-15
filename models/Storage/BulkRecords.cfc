/** Bounded identity reads retain database collation and caller order without per-row queries. */
component {

    public array function read( required any queryFactory, required array identities ) {
        var result = [];
        for ( var offset = 1; offset <= arguments.identities.len(); offset += 100 ) {
            var size = min( 100, arguments.identities.len() - offset + 1 );
            var combined = javacast( "null", "" );
            for ( var index = 1; index <= size; index++ ) {
                var identity = arguments.identities[ offset + index - 1 ];
                var query = arguments
                    .queryFactory()
                    .selectRaw( "*, ? AS megaphoneBulkOrdinal", [ { "value": index, "cfsqltype": "integer" } ] );
                for ( var key in identity ) {
                    if ( isArray( identity[ key ] ) ) {
                        query.whereIn( key, identity[ key ] );
                    } else {
                        query.where( key, identity[ key ] );
                    }
                }
                if ( isNull( combined ) ) {
                    combined = query;
                } else {
                    combined.unionAll( query );
                }
                result.append( [] );
            }
            for ( var row in combined.get() ) {
                var ordinal = val( row.megaphoneBulkOrdinal );
                structDelete( row, "megaphoneBulkOrdinal" );
                result[ offset + ordinal - 1 ].append( row );
            }
        }
        return result;
    }

    /** Keep wide inserts below conservative driver bind limits as well as 100 rows. */
    public numeric function insertSize( required struct row ) {
        return max( 1, min( 100, int( 900 / structCount( arguments.row ) ) ) );
    }

}
