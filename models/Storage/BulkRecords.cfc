/** Bounded identity reads retain database collation and caller order without per-row queries. */
component {

    // A BulkRecords instance belongs to one store operation, never a shared request cache.
    variables.expectedSourcePaths = {};
    variables.canonicalSourcePaths = {};
    variables.sourceIdentities = createObject( "java", "java.util.IdentityHashMap" ).init();

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
        var identity = sourceIdentity( arguments.instance );
        if ( !structKeyExists( identity, arguments.mapping ) ) {
            identity[ arguments.mapping ] = isStockMetadata(
                componentMetadata( arguments.instance ),
                arguments.mapping
            );
        }
        return identity[ arguments.mapping ];
    }

    private struct function sourceIdentity( required any instance ) {
        if ( !variables.sourceIdentities.containsKey( arguments.instance ) ) {
            variables.sourceIdentities.put( arguments.instance, {} );
        }
        return variables.sourceIdentities.get( arguments.instance );
    }

    private struct function componentMetadata( required any instance ) {
        var identity = sourceIdentity( arguments.instance );
        if ( !structKeyExists( identity, "metadata" ) ) {
            identity.metadata = getMetadata( arguments.instance );
        }
        return identity.metadata;
    }

    private boolean function isStockMetadata( required struct metadata, required string mapping ) {
        if ( !len( arguments.metadata.path ?: "" ) ) {
            return false;
        }
        if ( !structKeyExists( variables.expectedSourcePaths, arguments.mapping ) ) {
            var expected = getMetadata( createObject( "component", arguments.mapping ) );
            if ( !len( expected.path ?: "" ) ) {
                return false;
            }
            variables.expectedSourcePaths[ arguments.mapping ] = canonicalSourcePath( expected.path );
        }
        return compare(
            canonicalSourcePath( arguments.metadata.path ),
            variables.expectedSourcePaths[ arguments.mapping ]
        ) == 0;
    }

    private string function canonicalSourcePath( required string path ) {
        if ( !structKeyExists( variables.canonicalSourcePaths, arguments.path ) ) {
            variables.canonicalSourcePaths[ arguments.path ] = createObject( "java", "java.io.File" )
                .init( arguments.path )
                .getCanonicalPath();
        }
        return variables.canonicalSourcePaths[ arguments.path ];
    }

    /** Only qb's public executor with the unmodified PostgreSQL compiler supports this opt-in path. */
    public boolean function supportsReturning( required any query ) {
        var metadata = componentMetadata( arguments.query );
        if ( !isStockMetadata( metadata, "qb.models.Query.QueryBuilder" ) ) {
            return false;
        }
        var grammar = arguments.query.getGrammar();
        if ( isCustomFunction( grammar.getResolvedGrammar ?: "" ) ) {
            grammar = grammar.getResolvedGrammar();
        }
        if ( !isStockComponent( grammar, "qb.models.Grammars.PostgresGrammar" ) ) {
            return false;
        }
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

    /** Public typed-cell callers retain complete per-row validation. */
    public array function insertReferences(
        required any query,
        required array values,
        required array identities,
        required array columns,
        required any queryFactory,
        required string tableName,
        struct templates = {}
    ) {
        var options = structCopy( arguments );
        structDelete( options, "stockTypes" );
        return writeReferenceRows( argumentCollection = options );
    }

    /** Internal stock-store boundary: values have already passed the stores' private typed preparation. */
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
        var options = structCopy( arguments );
        structDelete( options, "stockTypes" );
        structDelete( options, "store" );
        structDelete( options, "types" );
        if (
            isStockComponent( arguments.store, "megaphone.models.Storage.EventStore" ) || isStockComponent(
                arguments.store,
                "megaphone.models.Storage.DeliveryStore"
            )
        ) {
            options.stockTypes = arguments.types;
        } else {
            // A custom producer cannot opt its arbitrary rows out of public validation.
            options.values = typedRows( arguments.values, arguments.types );
        }
        return writeReferenceRows( argumentCollection = options );
    }

    /** Fresh UUIDs identify returned inserts; only unresolved identities need a database read. */
    private array function writeReferenceRows(
        required any query,
        required array values,
        required array identities,
        required array columns,
        required any queryFactory,
        required string tableName,
        struct templates = {},
        struct stockTypes = {}
    ) {
        var compiled = compileReferenceInsert(
            arguments.query,
            arguments.values,
            arguments.columns,
            arguments.templates,
            arguments.stockTypes
        );
        var inserted = arguments.query.runQuery(
            // A SELECT-bearing statement exposes INSERT RETURNING rows on Lucee as well as BoxLang.
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
            var originalId = arguments.values[ index ].id;
            var id = isStruct( originalId ) ? originalId.value : originalId;
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

    /** Reuse only public-compiler placeholder tuples for known typed scalar inputs. */
    private struct function compileReferenceInsert(
        required any query,
        required array values,
        required array columns,
        required struct templates,
        struct stockTypes = {}
    ) {
        if (
            !supportsReturning( arguments.query ) || !isStockComponent(
                arguments.query.getUtils(),
                "qb.models.Query.QueryUtils"
            ) || !hasIdentityColumnFormatter( arguments.query )
        ) {
            return compileReferenceInsertFallback( argumentCollection = arguments );
        }
        var stock = !arguments.stockTypes.isEmpty();
        var sample = stock ? typedRows( [ arguments.values[ 1 ] ], arguments.stockTypes )[ 1 ] : arguments.values[ 1 ];
        var shape = referenceInsertShape( stock ? [ sample ] : arguments.values );
        if ( !shape.supported ) {
            return compileReferenceInsertFallback( argumentCollection = arguments );
        }
        var wrapping = {};
        if ( !isNull( arguments.query.getShouldWrapValues() ) ) {
            wrapping.value = arguments.query.getShouldWrapValues();
        }
        var firstRaw = arguments.values[ 1 ];
        var inputKinds = stock ? shape.names.map( ( name ) => isStruct( firstRaw[ name ] ) ) : [];
        var key = serializeJSON( [
            arguments.query.getTableName(),
            arguments.columns,
            shape.metadata,
            stock,
            inputKinds,
            wrapping
        ] );
        if ( !structKeyExists( arguments.templates, key ) ) {
            arguments.templates[ key ] = referenceInsertTemplate(
                arguments.query,
                sample,
                arguments.columns,
                shape.names
            );
            if ( stock && arguments.templates[ key ].supported ) {
                for ( var descriptor in arguments.templates[ key ].descriptors ) {
                    descriptor.fromBinding = isStruct( arguments.values[ 1 ][ descriptor.column ] );
                    descriptor.input = structCopy( sample[ descriptor.column ] );
                    // Direct stock bindings reproduce exactly the compiler's five normalized fields.
                    if (
                        structCount( descriptor.binding ) != 5 || !structKeyExists( descriptor.binding, "value" ) || !structKeyExists(
                            descriptor.binding,
                            "cfsqltype"
                        ) || !structKeyExists( descriptor.binding, "sqltype" ) || !structKeyExists(
                            descriptor.binding,
                            "null"
                        ) || !structKeyExists( descriptor.binding, "list" )
                    ) {
                        arguments.templates[ key ].supported = false;
                    }
                }
            }
        }
        var template = arguments.templates[ key ];
        if ( !template.supported ) {
            return compileReferenceInsertFallback( argumentCollection = arguments );
        }
        var bindings = [];
        var tuples = [];
        var utils = arguments.query.getUtils();
        var grammar = arguments.query.getGrammar();
        for ( var row in arguments.values ) {
            tuples.append( template.tuple );
            for ( var descriptor in template.descriptors ) {
                var cell = row[ descriptor.column ];
                var binding = {};
                if ( stock ) {
                    var rawValue = descriptor.fromBinding ? cell.value : cell;
                    var nullValue = descriptor.fromBinding ? ( cell.null ?: false ) : false;
                    if ( descriptor.temporal && !nullValue ) {
                        var temporalInput = cell;
                        if ( !descriptor.fromBinding ) {
                            descriptor.input.value = rawValue;
                            descriptor.input.null = false;
                            temporalInput = descriptor.input;
                        }
                        binding = utils.extractBinding( temporalInput, grammar );
                    } else {
                        binding = {
                            "value": rawValue,
                            "cfsqltype": descriptor.binding.cfsqltype,
                            "sqltype": descriptor.binding.sqltype,
                            "null": nullValue,
                            "list": descriptor.binding.list
                        };
                    }
                } else if ( !( cell.null ?: false ) && descriptor.temporal ) {
                    // Date/time normalization remains owned by the configured public qb utility.
                    binding = utils.extractBinding( cell, grammar );
                } else {
                    binding = structCopy( descriptor.binding );
                    binding.value = cell.value;
                    binding.null = structKeyExists( cell, "null" ) ? cell.null : false;
                }
                bindings.append( binding );
            }
        }
        return { "sql": template.prefix & tuples.toList( template.separator ) & template.suffix, "bindings": bindings };
    }

    /** QB14 always supplies its private identity callback, even without custom formatting. */
    private boolean function hasIdentityColumnFormatter( required any query ) {
        var formatter = arguments.query.getColumnFormatter();
        if ( isNull( formatter ) || !isCustomFunction( formatter ) || isClosure( formatter ) ) {
            return false;
        }
        var metadata = componentMetadata( formatter );
        return compareNoCase( metadata.name ?: "", "identityColumnFormatter" ) == 0 && compareNoCase(
            metadata.access ?: "",
            "private"
        ) == 0;
    }

    private struct function compileReferenceInsertFallback(
        required any query,
        required array values,
        required array columns,
        struct stockTypes = {}
    ) {
        var values = arguments.stockTypes.isEmpty() ? arguments.values : typedRows(
            arguments.values,
            arguments.stockTypes
        );
        arguments.query.returning( arguments.columns );
        var sql = arguments.query.insertIgnore( values = values, toSQL = true );
        return { "sql": sql, "bindings": arguments.query.getBindings() };
    }

    /** Unsupported values or metadata retain qb's original validation/normalization. */
    private struct function referenceInsertShape( required array values ) {
        var result = { "supported": false, "names": [], "metadata": [] };
        if ( arguments.values.isEmpty() || !isStruct( arguments.values[ 1 ] ) ) {
            return result;
        }
        result.names = arguments.values[ 1 ].keyArray().sort( "text" );
        for ( var name in result.names ) {
            var cell = arguments.values[ 1 ][ name ];
            if ( !referenceInsertCell( cell ) ) {
                return result;
            }
            var metadata = structNew( "ordered" );
            for ( var key in cell.keyArray().sort( "text" ) ) {
                if ( key != "value" && key != "null" ) {
                    metadata[ key ] = cell[ key ];
                }
            }
            result.metadata.append( { "column": name, "binding": metadata } );
        }
        for ( var row in arguments.values ) {
            if ( !isStruct( row ) || structCount( row ) != result.names.len() ) {
                return result;
            }
            for ( var descriptor in result.metadata ) {
                if ( !structKeyExists( row, descriptor.column ) ) {
                    return result;
                }
                var cell = row[ descriptor.column ];
                if (
                    !isStruct( cell ) || !structKeyExists( cell, "value" ) || isNull( cell.value ) || !isSimpleValue(
                        cell.value
                    ) || isBinary( cell.value ) || ( structKeyExists( cell, "null" ) && !isBoolean( cell.null ) )
                ) {
                    return result;
                }
                var metadataCount = structCount( cell ) - 1 - ( structKeyExists( cell, "null" ) ? 1 : 0 );
                if ( metadataCount != structCount( descriptor.binding ) ) {
                    return result;
                }
                for ( var key in descriptor.binding ) {
                    if ( !structKeyExists( cell, key ) || compare( cell[ key ], descriptor.binding[ key ] ) != 0 ) {
                        return result;
                    }
                }
            }
        }
        result.supported = true;
        return result;
    }

    private boolean function referenceInsertCell( any cell ) {
        if (
            isNull( arguments.cell ) || !isStruct( arguments.cell ) || !structKeyExists( arguments.cell, "value" ) || isNull(
                arguments.cell.value
            ) || !isSimpleValue( arguments.cell.value ) || isBinary( arguments.cell.value ) || !structKeyExists(
                arguments.cell,
                "cfsqltype"
            ) || !isSimpleValue( arguments.cell.cfsqltype )
        ) {
            return false;
        }
        for ( var key in arguments.cell ) {
            if (
                !listFindNoCase( "value,cfsqltype,sqltype,null,list", key ) || isNull( arguments.cell[ key ] ) || !isSimpleValue(
                    arguments.cell[ key ]
                )
            ) {
                return false;
            }
        }
        if (
            ( arguments.cell.list ?: false ) || (
                structKeyExists( arguments.cell, "null" ) && !isBoolean( arguments.cell.null )
            )
        ) {
            return false;
        }
        return listFindNoCase(
            "varchar,char,nvarchar,nchar,longvarchar,longnvarchar,integer,bigint,smallint,tinyint,timestamp,date,time",
            reReplaceNoCase( arguments.cell.cfsqltype, "^CF_SQL_", "" )
        ) > 0;
    }

    /** Marker names identify the public compiler's binding order without interpreting column SQL. */
    private struct function referenceInsertTemplate(
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
