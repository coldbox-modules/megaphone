/** Small preference reader avoids loading admission compilers for a lookup. */
component {

    variables.sources = new megaphone.models.Storage.StockSourceIdentity();

    /** Validated stock preference identities can use one bounded PostgreSQL JSON parameter per batch. */
    public array function read(
        required any store,
        required any queryFactory,
        required array identities,
        required string tableName,
        struct queryOptions = {}
    ) {
        if ( arguments.identities.isEmpty() ) {
            return [];
        }
        var query = arguments.queryFactory();
        if (
            !variables.sources.isStockComponent( arguments.store, "megaphone.models.Storage.PreferenceStore" ) ||
            !variables.sources.supportsReturning( query ) || !variables.sources.isStockComponent(
                query.getUtils(),
                "qb.models.Query.QueryUtils"
            ) ||
            !variables.sources.hasIdentityColumnFormatter( query )
        ) {
            return new megaphone.models.Storage.BulkRecords().readPreferencesFallback(
                queryFactory = arguments.queryFactory,
                identities = arguments.identities,
                tableName = arguments.tableName,
                queryOptions = arguments.queryOptions,
                firstQuery = query
            );
        }
        var grammar = query.getGrammar();
        if ( isCustomFunction( grammar.getResolvedGrammar ?: "" ) ) {
            grammar = grammar.getResolvedGrammar();
        }
        var result = [];
        var offset = 1;
        while ( offset <= arguments.identities.len() ) {
            var rows = [];
            var characters = 2;
            while ( offset + rows.len() <= arguments.identities.len() && rows.len() < 1000 ) {
                var identity = arguments.identities[ offset + rows.len() ];
                var encoded = serializeJSON( {
                    "ordinal": rows.len() + 1,
                    "c1": toString( identity.recipientType ),
                    "c2": toString( identity.recipientId ),
                    "c3": toString( identity.notificationType ),
                    "c4": identity.scopeKey
                } );
                // A single unusually large scope list retains the original parameterized implementation.
                if ( len( encoded ) > 1048576 && !rows.isEmpty() ) {
                    break;
                }
                if ( len( encoded ) > 1048576 ) {
                    var remaining = arguments.identities.slice( offset );
                    var fallback = new megaphone.models.Storage.BulkRecords().readPreferencesFallback(
                        arguments.queryFactory,
                        remaining,
                        arguments.tableName,
                        arguments.queryOptions
                    );
                    result.append( fallback, true );
                    return result;
                }
                if ( !rows.isEmpty() && characters + len( encoded ) + 1 > 1048576 ) {
                    break;
                }
                rows.append( encoded );
                characters += len( encoded ) + 1;
                result.append( [] );
            }
            query.reset().mergeDefaultOptions( arguments.queryOptions );
            var column = ( name ) => grammar.wrapColumn( query.mapToColumnType( name ) );
            query.fromRaw(
                "JSONB_TO_RECORDSET(CAST(? AS JSONB)) AS " & column( "megaphone_preference_batch" ) &
                "(" & column( "ordinal" ) & " INTEGER, " & column( "c1" ) & " TEXT, " & column( "c2" ) &
                " TEXT, " & column( "c3" ) & " TEXT, " & column( "c4" ) & " TEXT[])",
                [
                    {
                        "value": "[" & rows.toList( "," ) & "]",
                        "cfsqltype": "varchar",
                        "null": false,
                        "list": false
                    }
                ]
            );
            query.crossJoin( arguments.tableName & " AS megaphone_preference_row" );
            query
                .select( "megaphone_preference_row.*" )
                .addSelect( "megaphone_preference_batch.ordinal AS megaphoneBulkOrdinal" );
            query.whereColumn( "megaphone_preference_row.recipientType", "=", "megaphone_preference_batch.c1" );
            query.whereColumn( "megaphone_preference_row.recipientId", "=", "megaphone_preference_batch.c2" );
            query.whereColumn( "megaphone_preference_row.notificationType", "=", "megaphone_preference_batch.c3" );
            query.whereRaw(
                column( "megaphone_preference_row.scopeKey" ) & " = ANY(" & column( "megaphone_preference_batch.c4" ) & ")"
            );
            for ( var row in query.get() ) {
                var ordinal = val( row.megaphoneBulkOrdinal );
                structDelete( row, "megaphoneBulkOrdinal" );
                result[ offset + ordinal - 1 ].append( row );
            }
            offset += rows.len();
        }
        return result;
    }

}
