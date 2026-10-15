/** Bounded identity reads retain database collation and caller order without per-row queries. */
component {

    public array function read(
        required any queryFactory,
        required array identities,
        required string tableName,
        array columns = []
    ) {
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
                    if ( arguments.columns.isEmpty() ) {
                        query.selectRaw(
                            "*, ? AS megaphoneBulkOrdinal",
                            [ { "value": index, "cfsqltype": "integer" } ]
                        );
                    } else {
                        query
                            .select( arguments.columns )
                            .selectRaw( "? AS megaphoneBulkOrdinal", [ { "value": index, "cfsqltype": "integer" } ] );
                    }
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

    /** A mapping alias may rename the same stock component; subclasses still have different source files. */
    public boolean function isStockComponent( required any instance, required string mapping ) {
        var actual = getMetadata( arguments.instance );
        var expected = getMetadata( createObject( "component", arguments.mapping ) );
        if ( !len( actual.path ?: "" ) || !len( expected.path ?: "" ) ) {
            return false;
        }
        var actualPath = createObject( "java", "java.io.File" ).init( actual.path ).getCanonicalPath();
        var expectedPath = createObject( "java", "java.io.File" ).init( expected.path ).getCanonicalPath();
        return compare( actualPath, expectedPath ) == 0;
    }

    /** Only qb's public executor with the unmodified PostgreSQL compiler supports this opt-in path. */
    public boolean function supportsReturning( required any query ) {
        if ( !isStockComponent( arguments.query, "qb.models.Query.QueryBuilder" ) ) {
            return false;
        }
        var grammar = arguments.query.getGrammar();
        if ( isCustomFunction( grammar.getResolvedGrammar ?: "" ) ) {
            grammar = grammar.getResolvedGrammar();
        }
        if ( !isStockComponent( grammar, "qb.models.Grammars.PostgresGrammar" ) ) {
            return false;
        }
        var metadata = getMetadata( arguments.query );
        while ( isStruct( metadata ) ) {
            for ( var method in metadata.functions ?: [] ) {
                if ( compareNoCase( method.name, "runQuery" ) == 0 ) {
                    return compareNoCase( method.access ?: "", "public" ) == 0;
                }
            }
            if ( !isStruct( metadata.extends ?: "" ) ) {
                break;
            }
            metadata = metadata.extends;
        }
        return false;
    }

    /** Fresh UUIDs identify returned inserts; only unresolved identities need a database read. */
    public array function insertReferences(
        required any query,
        required array values,
        required array identities,
        required array columns,
        required any queryFactory,
        required string tableName
    ) {
        var sql = arguments.query.returning( arguments.columns ).insertIgnore( values = arguments.values, toSQL = true );
        var inserted = arguments.query.runQuery(
            // A SELECT-bearing statement exposes INSERT RETURNING rows on Lucee as well as BoxLang.
            sql = "WITH ""megaphone_inserted"" AS (" & sql & ") SELECT * FROM ""megaphone_inserted""",
            bindings = arguments.query.getBindings(),
            returnObject = "query"
        );
        var byId = {};
        for ( var row in inserted ) {
            byId[ toString( row.id ) ] = row;
        }
        var result = [];
        var unresolved = [];
        var ordinals = [];
        for ( var index = 1; index <= arguments.values.len(); index++ ) {
            var id = arguments.values[ index ].id.value;
            if ( structKeyExists( byId, id ) ) {
                result.append( [ byId[ id ] ] );
            } else {
                result.append( [] );
                unresolved.append( arguments.identities[ index ] );
                ordinals.append( index );
            }
        }
        if ( !unresolved.isEmpty() ) {
            var existing = read(
                arguments.queryFactory,
                unresolved,
                arguments.tableName,
                arguments.columns
            );
            for ( var index = 1; index <= existing.len(); index++ ) {
                result[ ordinals[ index ] ] = existing[ index ];
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
