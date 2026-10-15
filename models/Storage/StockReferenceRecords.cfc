/** Small stock-only executor; generic compilers and replay readers load only when required. */
component {

    variables.sources = new megaphone.models.Storage.StockSourceIdentity();
    public boolean function isStockComponent( required any instance, required string mapping ) {
        return variables.sources.isStockComponent( argumentCollection = arguments );
    }
    public boolean function supportsReturning( required any query ) {
        return variables.sources.supportsReturning( argumentCollection = arguments );
    }
    private any function fallback() {
        if ( !structKeyExists( variables, "fallbackRecords" ) ) {
            variables.fallbackRecords = new megaphone.models.Storage.BulkRecords();
        }
        return variables.fallbackRecords;
    }
    public array function insertStockReferences(
        required any store,
        required struct types,
        required any query,
        required array values,
        required array identities,
        required array columns,
        required any queryFactory,
        required string tableName,
        struct templates = {}
    ) {
        if (
            !(
                isStockComponent( arguments.store, "megaphone.models.Storage.EventStore" ) || isStockComponent(
                    arguments.store,
                    "megaphone.models.Storage.DeliveryStore"
                )
            ) || !supportsReturning( arguments.query ) || !isStockComponent(
                arguments.query.getUtils(),
                "qb.models.Query.QueryUtils"
            ) || !variables.sources.hasIdentityColumnFormatter( arguments.query )
        ) {
            return fallback().insertStockReferences( argumentCollection = arguments );
        }
        var compiled = compile(
            arguments.query,
            arguments.values,
            arguments.columns,
            arguments.types,
            arguments.templates
        );
        if ( !compiled.supported ) {
            return fallback().insertStockReferences( argumentCollection = arguments );
        }
        var inserted = arguments.query.runQuery(
            sql = "WITH ""megaphone_inserted"" AS (" & compiled.sql & ") SELECT * FROM ""megaphone_inserted""",
            bindings = compiled.bindings,
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
            var original = arguments.values[ index ].id;
            var id = isStruct( original ) ? original.value : original;
            if ( structKeyExists( byId, id ) ) {
                result.append( [ byId[ id ] ] );
            } else {
                result.append( [] );
                unresolved.append( arguments.identities[ index ] );
                ordinals.append( index );
            }
        }
        if ( !unresolved.isEmpty() ) {
            var bulk = fallback();
            var existing = bulk.read(
                arguments.queryFactory,
                bulk.typedRows( unresolved, arguments.types ),
                arguments.tableName,
                arguments.columns
            );
            for ( var index = 1; index <= existing.len(); index++ ) {
                result[ ordinals[ index ] ] = existing[ index ];
            }
        }
        return result;
    }
    /** Only privately prepared stock rows qualify; unsupported bindings retain the original compiler. */
    private struct function compile(
        required any query,
        required array values,
        required array columns,
        required struct types,
        required struct templates
    ) {
        var first = arguments.values[ 1 ];
        var names = first.keyArray().sort( "text" );
        var sample = {};
        for ( var name in names ) {
            var cell = first[ name ];
            sample[ name ] = isStruct( cell ) ? cell : {
                "value": cell,
                "cfsqltype": arguments.types[ name ],
                "null": false,
                "list": false
            };
            if (
                !structKeyExists( sample[ name ], "value" ) || isNull( sample[ name ].value ) || !isSimpleValue(
                    sample[ name ].value
                ) || isBinary( sample[ name ].value ) || ( sample[ name ].list ?: false )
            ) {
                return { "supported": false };
            }
        }
        var wrapping = {};
        if ( !isNull( arguments.query.getShouldWrapValues() ) ) {
            wrapping.value = arguments.query.getShouldWrapValues();
        }
        var key = serializeJSON( [
            "stock-executor",
            arguments.query.getTableName(),
            arguments.columns,
            arguments.types,
            names.map( ( name ) => isStruct( first[ name ] ) ),
            wrapping
        ] );
        if ( !structKeyExists( arguments.templates, key ) ) {
            var template = referenceInsertTemplate(
                arguments.query,
                sample,
                arguments.columns,
                names
            );
            if ( template.supported ) {
                for ( var descriptor in template.descriptors ) {
                    descriptor.fromBinding = isStruct( first[ descriptor.column ] );
                    descriptor.input = structCopy( sample[ descriptor.column ] );
                    if (
                        structCount( descriptor.binding ) != 5 || !structKeyExists( descriptor.binding, "value" ) || !structKeyExists(
                            descriptor.binding,
                            "cfsqltype"
                        ) || !structKeyExists( descriptor.binding, "sqltype" ) || !structKeyExists(
                            descriptor.binding,
                            "null"
                        ) || !structKeyExists( descriptor.binding, "list" )
                    ) {
                        template.supported = false;
                    }
                }
            }
            arguments.templates[ key ] = template;
        }
        if ( !arguments.templates[ key ].supported ) {
            return { "supported": false };
        }
        return compileStockRecordsetInsert( arguments.query, arguments.values, arguments.templates[ key ] );
    }
    public struct function compileStockRecordsetInsert(
        required any query,
        required array values,
        required struct template
    ) {
        var grammar = arguments.query.getGrammar();
        if ( isCustomFunction( grammar.getResolvedGrammar ?: "" ) ) {
            grammar = grammar.getResolvedGrammar();
        }
        var utils = arguments.query.getUtils();
        if ( !structKeyExists( variables, "temporalValues" ) ) {
            variables.temporalValues = createObject( "java", "java.util.IdentityHashMap" ).init();
        }
        var columns = [];
        var definitions = [];
        for ( var descriptor in arguments.template.descriptors ) {
            var type = lCase( reReplaceNoCase( descriptor.binding.cfsqltype, "^CF_SQL_", "" ) );
            var sqlType = "";
            if ( listFind( "varchar,char,nvarchar,nchar,longvarchar,longnvarchar", type ) ) {
                sqlType = "TEXT";
            } else if ( type == "integer" ) {
                sqlType = "INTEGER";
            } else if ( type == "timestamp" ) {
                sqlType = "TIMESTAMP";
            } else {
                return { "supported": false };
            }
            columns.append( descriptor.column );
            definitions.append(
                grammar.wrapColumn( arguments.query.mapToColumnType( descriptor.column ) ) & " " & sqlType
            );
        }
        var packed = [];
        for ( var row in arguments.values ) {
            var item = {};
            for ( var descriptor in arguments.template.descriptors ) {
                var cell = row[ descriptor.column ];
                var value = descriptor.fromBinding ? cell.value : cell;
                if ( descriptor.fromBinding && ( cell.null ?: false ) ) {
                    // Missing JSON fields become SQL NULL, including on engines without full null structs.
                    continue;
                }
                if ( descriptor.temporal ) {
                    if ( !variables.temporalValues.containsKey( value ) ) {
                        descriptor.input.value = value;
                        descriptor.input.null = false;
                        var normalized = utils.extractBinding(
                            descriptor.fromBinding ? cell : descriptor.input,
                            grammar
                        );
                        variables.temporalValues.put( value, normalized.value );
                    }
                    value = variables.temporalValues.get( value );
                }
                item[ descriptor.column ] = value;
            }
            packed.append( item );
        }
        var encoded = serializeJSON( packed );
        if ( len( encoded ) > 8388608 ) {
            return { "supported": false };
        }
        var source = arguments.query.newQuery();
        source.fromRaw(
            "JSONB_TO_RECORDSET(CAST(? AS JSONB)) AS " & grammar.wrapColumn(
                arguments.query.mapToColumnType( "megaphone_admission_rows" )
            ) &
            "(" & definitions.toList( ", " ) & ")",
            [
                {
                    "value": encoded,
                    "cfsqltype": "varchar",
                    "null": false,
                    "list": false
                }
            ]
        );
        source.select( columns );
        // PostgreSQL needs a WHERE clause to disambiguate INSERT SELECT followed by ON CONFLICT.
        source.whereRaw( "1 = 1" );
        var sql = arguments.query.insertUsing( source = source, columns = columns, toSQL = true );
        return { "supported": true, "sql": sql & arguments.template.suffix, "bindings": arguments.query.getBindings() };
    }

    public struct function referenceInsertTemplate(
        required any query,
        required struct first,
        required array columns,
        required array names
    ) {
        var unsupported = { "supported": false };
        var marker = {};
        var markerColumns = {};
        for ( var index = 1; index <= arguments.names.len(); index++ ) {
            var name = arguments.names[ index ];
            var binding = structCopy( arguments.first[ name ] );
            binding.name = "megaphone_column_" & index;
            marker[ name ] = binding;
            markerColumns[ binding.name ] = name;
        }
        arguments.query.returning( arguments.columns );
        var oneSQL = arguments.query.insertIgnore( values = [ marker ], toSQL = true );
        var one = arguments.query.getBindings();
        var twoSQL = arguments.query.insertIgnore( values = [ marker, marker ], toSQL = true );
        var two = arguments.query.getBindings();
        if ( one.len() != arguments.names.len() || two.len() != one.len() * 2 ) {
            return unsupported;
        }
        var descriptors = [];
        var seen = {};
        for ( var index = 1; index <= one.len(); index++ ) {
            var binding = one[ index ];
            if (
                !structKeyExists( binding, "name" ) || !structKeyExists( markerColumns, binding.name ) || structKeyExists(
                    seen,
                    binding.name
                ) || compare( serializeJSON( binding ), serializeJSON( two[ index ] ) ) != 0 || compare(
                    serializeJSON( binding ),
                    serializeJSON( two[ index + one.len() ] )
                ) != 0
            ) {
                return unsupported;
            }
            var column = markerColumns[ binding.name ];
            seen[ binding.name ] = true;
            var prototype = structCopy( binding );
            structDelete( prototype, "name" );
            var temporal = listFindNoCase(
                "timestamp,date,time",
                reReplaceNoCase( prototype.cfsqltype, "^CF_SQL_", "" )
            ) > 0;
            if (
                !temporal && compare(
                    serializeJSON( prototype.value ),
                    serializeJSON( arguments.first[ column ].value )
                ) != 0
            ) {
                return unsupported;
            }
            descriptors.append( { "column": column, "binding": prototype, "temporal": temporal } );
        }
        var position = 1;
        while ( position <= len( oneSQL ) ) {
            var match = reFind(
                "\(\s*\?(?:\s*,\s*\?)*\s*\)",
                oneSQL,
                position,
                true
            );
            if ( !match.pos[ 1 ] ) {
                return unsupported;
            }
            var tuple = mid( oneSQL, match.pos[ 1 ], match.len[ 1 ] );
            var prefix = left( oneSQL, match.pos[ 1 ] - 1 );
            var suffix = mid( oneSQL, match.pos[ 1 ] + match.len[ 1 ], len( oneSQL ) );
            var bodyLength = len( twoSQL ) - len( prefix ) - len( suffix );
            if (
                len( tuple ) - len( replace( tuple, "?", "", "all" ) ) == one.len() && bodyLength > len( tuple ) * 2 && left(
                    twoSQL,
                    len( prefix )
                ) == prefix && right( twoSQL, len( suffix ) ) == suffix
            ) {
                var body = mid( twoSQL, len( prefix ) + 1, bodyLength );
                var separator = mid( body, len( tuple ) + 1, len( body ) - len( tuple ) * 2 );
                if (
                    left( body, len( tuple ) ) == tuple && right( body, len( tuple ) ) == tuple && trim( separator ) == ","
                ) {
                    return {
                        "supported": true,
                        "prefix": prefix,
                        "tuple": tuple,
                        "separator": separator,
                        "suffix": suffix,
                        "descriptors": descriptors
                    };
                }
            }
            position = match.pos[ 1 ] + match.len[ 1 ];
        }
        return unsupported;
    }

}
