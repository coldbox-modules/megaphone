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
            var templates = {};
            var wrapping = {};
            if ( isCustomFunction( query.getShouldWrapValues ?: "" ) ) {
                var configuredWrapping = query.getShouldWrapValues();
                if ( !isNull( configuredWrapping ) ) {
                    wrapping.value = configuredWrapping;
                }
            }
            for ( var index = 1; index <= size; index++ ) {
                var identity = arguments.identities[ offset + index - 1 ];
                var shape = identityShape( identity );
                if ( shape.cacheable && structKeyExists( templates, shape.key ) ) {
                    var template = templates[ shape.key ];
                    branches.append( template.sql );
                    var values = [ index ];
                    values.append( shape.values, true );
                    for ( var position = 1; position <= template.bindings.len(); position++ ) {
                        var binding = structCopy( template.bindings[ position ] );
                        binding.value = values[ position ];
                        bindings.append( binding );
                    }
                } else {
                    query.reset().from( arguments.tableName );
                    restoreWrapping( query, wrapping );
                    query.selectRaw( "*, ? AS megaphoneBulkOrdinal", [ { "value": index, "cfsqltype": "integer" } ] );
                    for ( var key in shape.keys ) {
                        if ( isArray( identity[ key ] ) ) {
                            query.whereIn( key, identity[ key ] );
                        } else {
                            query.where( key, identity[ key ] );
                        }
                    }
                    var sql = query.toSQL();
                    var compiledBindings = query.getBindings();
                    branches.append( sql );
                    bindings.append( compiledBindings, true );
                    if ( shape.cacheable && reusableBindings( compiledBindings, shape.values, index ) ) {
                        templates[ shape.key ] = {
                            "sql": sql,
                            "bindings": compiledBindings.map( ( item ) => structCopy( item ) )
                        };
                    }
                }
                result.append( [] );
            }
            query.reset();
            restoreWrapping( query, wrapping );
            // All values remain bound parameters; table/column syntax came from the configured grammar.
            query.fromRaw( "(" & branches.toList( " UNION ALL " ) & ") megaphone_bulk_records" );
            query.addBindings( bindings, "from" );
            for ( var row in query.get() ) {
                var ordinal = val( row.megaphoneBulkOrdinal );
                structDelete( row, "megaphoneBulkOrdinal" );
                result[ offset + ordinal - 1 ].append( row );
            }
        }
        return result;
    }

    /** Explicit metadata permits SQL reuse; inferred or value-normalized types keep the compiler path. */
    private struct function identityShape( required struct identity ) {
        var keys = arguments.identity.keyArray().sort( "text" );
        var result = {
            "cacheable": true,
            "keys": keys,
            "values": [],
            "key": ""
        };
        var shape = [];
        for ( var key in keys ) {
            var value = arguments.identity[ key ];
            var values = isArray( value ) ? value : [ value ];
            var entry = { "column": key, "array": isArray( value ), "bindings": [] };
            for ( var item in values ) {
                if (
                    !isStruct( item ) || !structKeyExists( item, "value" ) || isNull( item.value ) ||
                    !structKeyExists( item, "cfsqltype" ) || !isSimpleValue( item.value ) || isBinary( item.value ) ||
                    structKeyExists( item, "isExpression" ) || ( item.list ?: false )
                ) {
                    result.cacheable = false;
                    continue;
                }
                var type = reReplaceNoCase( item.cfsqltype, "^CF_SQL_", "" );
                if (
                    !listFindNoCase(
                        "varchar,char,nvarchar,nchar,longvarchar,longnvarchar,integer,bigint,smallint,tinyint",
                        type
                    )
                ) {
                    result.cacheable = false;
                    continue;
                }
                var metadata = structNew( "ordered" );
                for ( var name in item.keyArray().sort( "text" ) ) {
                    if ( name == "value" ) {
                        continue;
                    }
                    if ( isNull( item[ name ] ) || !isSimpleValue( item[ name ] ) ) {
                        result.cacheable = false;
                        continue;
                    }
                    metadata[ name ] = item[ name ];
                }
                entry.bindings.append( metadata );
                result.values.append( item.value );
            }
            shape.append( entry );
        }
        if ( result.cacheable ) {
            result.key = hash( serializeJSON( shape ), "SHA-256" );
        }
        return result;
    }

    /** Do not reuse a grammar/custom normalizer that changes values or binding cardinality. */
    private boolean function reusableBindings(
        required array bindings,
        required array values,
        required numeric ordinal
    ) {
        if ( arguments.bindings.len() != arguments.values.len() + 1 ) {
            return false;
        }
        var expectedValues = [ arguments.ordinal ];
        expectedValues.append( arguments.values, true );
        for ( var index = 1; index <= arguments.bindings.len(); index++ ) {
            var binding = arguments.bindings[ index ];
            if (
                !isStruct( binding ) || !structKeyExists( binding, "value" ) || isNull( binding.value ) ||
                compare( serializeJSON( binding.value ), serializeJSON( expectedValues[ index ] ) ) != 0
            ) {
                return false;
            }
            for ( var key in binding ) {
                if ( isNull( binding[ key ] ) || !isSimpleValue( binding[ key ] ) ) {
                    return false;
                }
            }
        }
        return true;
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

    /** Storage columns have known SQL types; leave raw preparation/replay values unchanged. */
    public array function typedRows( required array rows, required struct types ) {
        var result = [];
        for ( var row in arguments.rows ) {
            var values = {};
            for ( var key in row ) {
                if ( isStruct( row[ key ] ) || !structKeyExists( arguments.types, key ) ) {
                    values[ key ] = row[ key ];
                } else {
                    values[ key ] = {
                        "value": row[ key ],
                        "cfsqltype": arguments.types[ key ],
                        "null": false,
                        "list": false
                    };
                }
            }
            result.append( values );
        }
        return result;
    }

    /** Keep wide inserts below conservative driver bind limits as well as 100 rows. */
    public numeric function insertSize( required struct row ) {
        return max( 1, min( 100, int( 900 / structCount( arguments.row ) ) ) );
    }

}
