/** Real PostgreSQL admission through both QB9 fallback and QB14 RETURNING. */
component extends="tests.resources.BulkNotificationSpecBase" {

    function run() {
        describe( "Reference-only durable storage", () => {
            aroundEach( ( spec ) => {
                transaction {
                    try {
                        variables.owner = new tests.resources.InboxRecipient().setId( createUUID() );
                        variables.adapter = new tests.resources.BulkReferenceQueueFixture();
                        variables.config.queue.queueAdapter = variables.adapter;
                        variables.counter = {
                            "count": 0,
                            "sql": [],
                            "inserts": [],
                            "results": [],
                            "executions": 0
                        };
                        variables.originalInterceptor = variables.grammar.getInterceptorService();
                        variables.observer = new tests.resources.ReferenceQueryObserver()
                            .setDelegate( variables.originalInterceptor )
                            .setCounter( variables.counter );
                        variables.grammar.setInterceptorService( variables.observer );
                        // The positive control proves the observer receives the actual execution hook.
                        var probe = variables.injector.getInstance( "QueryBuilder@qb" );
                        probe
                            .from( "megaphone_events" )
                            .whereRaw( "1 = 0" )
                            .get();
                        variables.fast = new megaphone.models.Storage.BulkRecords().supportsReturning(
                            variables.injector.getInstance( "QueryBuilder@qb" )
                        );
                        spec.body();
                    } finally {
                        transactionRollback();
                        restoreStores();
                        variables.grammar.setInterceptorService( variables.originalInterceptor );
                    }
                }
            } );
            it( "uses the explicitly requested public QB14 PostgreSQL executor and keeps QB9 fallback", () => {
                expect( variables.fast ).toBe( application.megaphoneRequireReturning ?: false );
            } );
            it( "resolves expected files without constructing them or accepting missing sources", () => {
                var sources = new megaphone.models.Storage.StockSourceIdentity();
                expect(
                    sources.isStockComponent( variables.events, "tests.resources.ExpectedSourceConstructionGuard" )
                ).toBeFalse();
                expect( sources.isStockComponent( variables.events, "tests.resources.DoesNotExistSource" ) ).toBeFalse();
                expect( sources.isStockComponent( variables.events, "megaphone.models.Storage.EventStore" ) ).toBeTrue();
            } );
            it( "loads generic reference machinery only when a stock replay needs a lookup", () => {
                if ( !variables.fast ) {
                    expect( variables.events.recordReferences( [ eventInput( createUUID() ) ] )[ 1 ].created ).toBeTrue();
                    return;
                }
                var executor = new megaphone.models.Storage.StockReferenceRecords();
                var typed = referenceRows( 1 )[ 1 ];
                var row = {};
                for ( var name in typed ) {
                    row[ name ] = name == "notificationMapping" ? typed[ name ] : typed[ name ].value;
                }
                var options = {
                    "store": variables.events,
                    "types": {
                        "id": "varchar",
                        "namespace": "varchar",
                        "eventKey": "varchar",
                        "version": "integer",
                        "type": "varchar",
                        "payloadHash": "varchar",
                        "payload": "varchar",
                        "createdDate": "timestamp",
                        "notificationMapping": "varchar"
                    },
                    "values": [ row ],
                    "identities": [ { "namespace": row.namespace, "eventKey": row.eventKey, "version": row.version } ],
                    "columns": [ "id", "type", "payloadHash" ],
                    "queryFactory": () => referenceQuery(),
                    "tableName": "megaphone_events"
                };
                var fresh = executor.insertStockReferences( argumentCollection = options, query = referenceQuery() );
                expect( fresh[ 1 ][ 1 ].id ).toBe( row.id );
                expect( getProperty( target = executor, name = "fallbackRecords", defaultValue = false ) ).toBeFalse();
                var replay = executor.insertStockReferences( argumentCollection = options, query = referenceQuery() );
                expect( replay[ 1 ][ 1 ].id ).toBe( row.id );
                expect( isObject( getProperty( executor, "fallbackRecords" ) ) ).toBeTrue();
                expect( variables.events.find( row.id ).payloadHash ).toBe( row.payloadHash );
            } );
            it( "recognizes the exact stock source through mapping aliases while retaining real admission", () => {
                var bulk = new megaphone.models.Storage.BulkRecords();
                var queryAlias = new qbStockAlias.models.Query.QueryBuilder( grammar = variables.grammar );
                // Adobe canonicalizes metadata names for aliases; physical stock ownership is the contract.
                expect( bulk.isStockComponent( queryAlias, "qb.models.Query.QueryBuilder" ) ).toBeTrue(
                    serializeJSON( {
                        "actual": getMetadata( queryAlias ).path,
                        "expected": expandPath( "/qb/models/Query/QueryBuilder.cfc" )
                    } )
                );
                expect( bulk.supportsReturning( queryAlias ) ).toBe( variables.fast );
                var eventAlias = variables.injector.getInstance( "megaphoneStockAlias.models.Storage.EventStore" );
                var deliveryAlias = variables.injector.getInstance( "megaphoneStockAlias.models.Storage.DeliveryStore" );
                expect( bulk.isStockComponent( eventAlias, "megaphone.models.Storage.EventStore" ) ).toBeTrue();
                expect( bulk.isStockComponent( deliveryAlias, "megaphone.models.Storage.DeliveryStore" ) ).toBeTrue();
                var event = eventAlias.recordReferences( [ eventInput( createUUID() ) ] )[ 1 ];
                var work = deliveryAlias.enqueueReferences( [ deliveryInput( event.id ) ] )[ 1 ];
                expect( event.created ).toBeTrue();
                expect( work.created ).toBeTrue();
                expect( variables.counter.count == 0 ).toBe( variables.fast );
                expect( deliveryAlias.find( work.id ).eventId ).toBe( event.id );
            } );
            it( "returns minimal fresh references over a 1000-row boundary without identity readbacks on the fast path", () => {
                var total = variables.fast ? 1001 : 101;
                var inputs = [];
                for ( var index = 1; index <= total; index++ ) {
                    inputs.append( eventInput( createUUID() ) );
                }
                var eventReferences = variables.events.recordReferences( inputs );
                expect( variables.counter.count == 0 ).toBe(
                    variables.fast,
                    serializeJSON( {
                        "inserts": variables.counter.inserts,
                        "readbacks": variables.counter.count,
                        "results": variables.counter.results,
                        "store": getMetadata( variables.events ).name
                    } )
                );
                expect( eventReferences.len() ).toBe( total );
                if ( variables.fast ) {
                    expect( variables.counter.inserts.map( ( item ) => item.rows ) ).toBe( [ 1000, 1 ] );
                    expect( variables.counter.results.map( ( item ) => item.rows ) ).toBe( [ 1000, 1 ] );
                    expect( variables.counter.inserts.every( ( item ) => item.bindings == 1 && item.json ) ).toBeTrue();
                }
                for ( var event in eventReferences ) {
                    expect( event.keyArray().sort( "text" ) ).toBe( [ "created", "id" ] );
                    expect( event.created ).toBeTrue();
                }
                variables.counter.count = 0;
                variables.counter.sql = [];
                variables.counter.inserts = [];
                variables.counter.results = [];
                var intents = eventReferences.map( ( event ) => deliveryInput( event.id ) );
                var deliveryReferences = variables.deliveries.enqueueReferences( intents );
                expect( variables.counter.count == 0 ).toBe( variables.fast );
                expect( deliveryReferences.len() ).toBe( total );
                if ( variables.fast ) {
                    expect( variables.counter.inserts.map( ( item ) => item.rows ) ).toBe( [ 1000, 1 ] );
                    expect( variables.counter.results.map( ( item ) => item.rows ) ).toBe( [ 1000, 1 ] );
                    expect( variables.counter.inserts.every( ( item ) => item.bindings == 1 && item.json ) ).toBeTrue();
                }
                for ( var work in deliveryReferences ) {
                    expect( work.keyArray().sort( "text" ) ).toBe( [
                        "availableDate",
                        "created",
                        "id",
                        "state"
                    ] );
                    expect( work.created ).toBeTrue();
                    expect( work.state ).toBe( "queued" );
                    expect( millisecondsBetween( work.availableDate, intents[ 1 ].availableDate ) ).toBe( 0 );
                }
            } );
            it( "resolves duplicate and replayed identities across chunks while retaining conflicts and narrow reads", () => {
                var input = eventInput( createUUID() );
                var repeated = [];
                for ( var index = 1; index <= ( variables.fast ? 1001 : 101 ); index++ ) {
                    repeated.append( input );
                }
                var eventReferences = variables.events.recordReferences( repeated );
                expect( eventReferences.filter( ( row ) => row.created ).len() ).toBe( 1 );
                expect( eventReferences.every( ( row ) => row.id == eventReferences[ 1 ].id ) ).toBeTrue();
                if ( variables.fast ) {
                    expect( variables.counter.sql.len() ).toBeGT( 0 );
                    expect( variables.counter.sql.toList( " " ) ).notToInclude( """payload""" );
                }
                variables.counter.sql = [];
                var intent = deliveryInput( eventReferences[ 1 ].id );
                var intents = repeated.map( () => intent );
                var deliveryReferences = variables.deliveries.enqueueReferences( intents );
                expect( deliveryReferences.filter( ( row ) => row.created ).len() ).toBe( 1 );
                expect( deliveryReferences.every( ( row ) => row.id == deliveryReferences[ 1 ].id ) ).toBeTrue();
                if ( variables.fast ) {
                    expect( variables.counter.sql.toList( " " ) ).notToInclude( """routingData""" );
                }
                intent.routingHash = "conflict";
                expect( () => variables.deliveries.enqueueReferences( [ intent ] ) ).toThrow( "Megaphone.Delivery.IdentityConflict" );
                expect( isNull( variables.events.find( eventReferences[ 1 ].id ) ) ).toBeTrue();
            } );
            it( "rolls back earlier chunks on an immutable event conflict", () => {
                var input = eventInput( createUUID() );
                var first = variables.events.recordReferences( [ input ] )[ 1 ];
                var batch = [];
                for ( var index = 1; index <= 101; index++ ) {
                    batch.append( eventInput( createUUID() ) );
                }
                input.payloadHash = "changed";
                batch.append( input );
                expect( () => variables.events.recordReferences( batch ) ).toThrow( "Megaphone.Events.IdentityConflict" );
                expect( isNull( variables.events.find( first.id ) ) ).toBeTrue();
                expect(
                    variables.injector
                        .getInstance( "QueryBuilder@qb" )
                        .from( "megaphone_events" )
                        .count()
                ).toBe( 0 );
            } );
            it( "reuses public compiler tuples and exact typed bindings across heterogeneous rows and chunks", () => {
                if ( !variables.fast ) {
                    var reference = variables.events.recordReferences( [ eventInput( createUUID() ) ] )[ 1 ];
                    expect( variables.counter.count ).toBeGT( 0 );
                    expect( variables.events.find( reference.id ).payload.text ).toBe( "'quoted ?'" );
                    return;
                }
                var rows = referenceRows( 101 );
                var query = referenceQuery();
                query.setCollectQueryLog( true );
                var compiles = { "sizes": [] };
                observeCompiler( query, compiles );
                var templates = {};
                var bulk = new megaphone.models.Storage.BulkRecords();
                var admitted = insertReferenceRows( bulk, query, rows, templates );
                expect( compiles.sizes ).toBe( [ 1, 2 ] );
                expect( templates.count() ).toBe( 1 );
                expect( admitted.len() ).toBe( rows.len() );
                var expected = referenceQuery();
                expected.returning( [ "id", "type", "payloadHash" ] );
                expected.insertIgnore( values = rows, toSQL = true );
                expect( query.getQueryLog()[ 1 ].bindings ).toBe( expected.getBindings() );
                for ( var index = 1; index <= rows.len(); index++ ) {
                    var stored = variables.events.find( admitted[ index ][ 1 ].id );
                    expect( stored.eventKey ).toBe( rows[ index ].eventKey.value );
                    expect( stored.payloadHash ).toBe( rows[ index ].payloadHash.value );
                    expect( stored.payload.text ).toBe( "'quoted ?' OR true --" & index );
                    expect( millisecondsBetween( stored.createdDate, rows[ index ].createdDate.value ) ).toBe( 0 );
                    expect( stored.notificationMapping ?: "" ).toBe( rows[ index ].notificationMapping.value );
                }
                var next = referenceQuery();
                observeCompiler( next, compiles );
                var nextRows = referenceRows( 3 );
                var nextResult = insertReferenceRows( bulk, next, nextRows, templates );
                expect( nextResult.len() ).toBe( 3 );
                expect( compiles.sizes ).toBe( [ 1, 2 ] );
            } );
            it( "uses the fixed stock schema with exact bindings but never trusts a custom store producer", () => {
                var bulk = new megaphone.models.Storage.BulkRecords();
                var customStore = new tests.resources.OverriddenReferenceEventStore();
                expect( bulk.isStockComponent( customStore, "megaphone.models.Storage.EventStore" ) ).toBeFalse();
                if ( !variables.fast ) {
                    var reference = variables.events.recordReferences( [ eventInput( createUUID() ) ] )[ 1 ];
                    expect( reference.created ).toBeTrue();
                    expect( variables.counter.count ).toBeGT( 0 );
                    return;
                }
                var types = {
                    "id": "varchar",
                    "namespace": "varchar",
                    "eventKey": "varchar",
                    "version": "integer",
                    "type": "varchar",
                    "payloadHash": "varchar",
                    "payload": "varchar",
                    "createdDate": "timestamp",
                    "notificationMapping": "varchar"
                };
                var rows = referenceRows( 101 ).map( ( row ) => {
                    var raw = {};
                    for ( var name in row ) {
                        raw[ name ] = name == "notificationMapping" ? row[ name ] : row[ name ].value;
                    }
                    return raw;
                } );
                var query = referenceQuery();
                query.setCollectQueryLog( true );
                var compiles = { "sizes": [] };
                observeCompiler( query, compiles );
                var admitted = bulk.insertStockReferences(
                    store = variables.events,
                    types = types,
                    query = query,
                    values = rows,
                    identities = [],
                    columns = [ "id", "type", "payloadHash" ],
                    queryFactory = () => referenceQuery(),
                    tableName = "megaphone_events"
                );
                expect( compiles.sizes ).toBe( [ 1, 2 ] );
                expect( admitted.len() ).toBe( 101 );
                var expected = referenceQuery();
                expected.returning( [ "id", "type", "payloadHash" ] );
                expected.insertIgnore( values = bulk.typedRows( rows, types ), toSQL = true );
                expect( query.getQueryLog()[ 1 ].bindings.len() ).toBe( 1 );
                var packed = deserializeJSON( query.getQueryLog()[ 1 ].bindings[ 1 ].value );
                var normalBindings = expected.getBindings();
                var names = rows[ 1 ].keyArray().sort( "text" );
                var position = 1;
                for ( var row in packed ) {
                    for ( var name in names ) {
                        var binding = normalBindings[ position++ ];
                        if ( binding.null ) {
                            expect( structKeyExists( row, name ) ).toBeFalse();
                        } else {
                            expect( row[ name ] ).toBe( binding.value );
                        }
                    }
                }
                for ( var index = 1; index <= rows.len(); index++ ) {
                    var stored = variables.events.find( admitted[ index ][ 1 ].id );
                    expect( stored.eventKey ).toBe( rows[ index ].eventKey );
                    expect( stored.notificationMapping ?: "" ).toBe( rows[ index ].notificationMapping.value );
                    expect( millisecondsBetween( stored.createdDate, rows[ index ].createdDate ) ).toBe( 0 );
                }
                var untrusted = referenceRows( 3 );
                untrusted[ 2 ].payloadHash.maxlength = 100;
                var fallback = referenceQuery();
                var fallbackCompiles = { "sizes": [] };
                observeCompiler( fallback, fallbackCompiles );
                var fallbackResult = bulk.insertStockReferences(
                    store = customStore,
                    types = types,
                    query = fallback,
                    values = untrusted,
                    identities = [],
                    columns = [ "id", "type", "payloadHash" ],
                    queryFactory = () => referenceQuery(),
                    tableName = "megaphone_events"
                );
                expect( fallbackCompiles.sizes ).toBe( [ 3 ] );
                expect( variables.events.find( fallbackResult[ 2 ][ 1 ].id ).payloadHash ).toBe(
                    untrusted[ 2 ].payloadHash.value
                );
                var generic = referenceQuery();
                var genericCompiles = { "sizes": [] };
                observeCompiler( generic, genericCompiles );
                var genericRows = referenceRows( 3 );
                genericRows[ 2 ].payloadHash.maxlength = 100;
                var genericResult = bulk.insertReferences(
                    query = generic,
                    values = genericRows,
                    identities = [],
                    columns = [ "id", "type", "payloadHash" ],
                    queryFactory = () => referenceQuery(),
                    tableName = "megaphone_events",
                    stockTypes = types
                );
                expect( genericCompiles.sizes ).toBe( [ 3 ] );
                expect( variables.events.find( genericResult[ 2 ][ 1 ].id ).payloadHash ).toBe(
                    genericRows[ 2 ].payloadHash.value
                );
            } );
            it( "rejects a private same-name formatter without invoking it and preserves its real renamed SQL columns", () => {
                var sources = new megaphone.models.Storage.StockSourceIdentity();
                if ( variables.fast ) {
                    expect( sources.hasIdentityColumnFormatter( referenceQuery() ) ).toBeTrue();
                    expect(
                        sources.hasIdentityColumnFormatter(
                            new qbStockAlias.models.Query.QueryBuilder( grammar = variables.grammar )
                        )
                    ).toBeTrue();
                }
                var owner = new tests.resources.SpoofedIdentityFormatter();
                var query = referenceQuery();
                query.setColumnFormatter( owner.formatter() );
                expect( getMetadata( query.getColumnFormatter() ).name ).toBe( "identityColumnFormatter" );
                expect( getMetadata( query.getColumnFormatter() ).access ).toBe( "private" );
                expect( sources.hasIdentityColumnFormatter( query ) ).toBeFalse();
                expect( owner.getCalls() ).toBe( 0 );
                var rows = referenceRows( 2 );
                for ( var row in rows ) {
                    row.sourcePayloadHash = row.payloadHash;
                    structDelete( row, "payloadHash" );
                }
                var compiles = { "sizes": [] };
                observeCompiler( query, compiles );
                if ( variables.fast ) {
                    var admitted = insertReferenceRows(
                        new megaphone.models.Storage.BulkRecords(),
                        query,
                        rows,
                        {}
                    );
                    expect( admitted.len() ).toBe( 2 );
                    expect( compiles.sizes ).toBe( [ 2 ] );
                } else {
                    query.insertIgnore( values = rows );
                }
                expect( owner.getCalls() ).toBeGT( 0 );
                for ( var row in rows ) {
                    expect( variables.events.find( row.id.value ).payloadHash ).toBe( row.sourcePayloadHash.value );
                }
            } );
            it( "retains full public compilation for unsupported metadata, expressions and custom formatters", () => {
                if ( !variables.fast ) {
                    var input = eventInput( createUUID() );
                    var reference = variables.events.recordReferences( [ input ] )[ 1 ];
                    expect( variables.events.recordReferences( [ input ] )[ 1 ].id ).toBe( reference.id );
                    return;
                }
                var rows = referenceRows( 3 );
                rows[ 2 ].payloadHash.maxlength = 100;
                var query = referenceQuery();
                rows[ 3 ].payloadHash = query.raw( "?", [ "expression-'? --" ] );
                var compiles = { "sizes": [] };
                observeCompiler( query, compiles );
                var admitted = insertReferenceRows(
                    new megaphone.models.Storage.BulkRecords(),
                    query,
                    rows,
                    {}
                );
                expect( compiles.sizes ).toBe( [ 3 ] );
                expect( variables.events.find( admitted[ 2 ][ 1 ].id ).payloadHash ).toBe( rows[ 2 ].payloadHash.value );
                expect( variables.events.find( admitted[ 3 ][ 1 ].id ).payloadHash ).toBe( "expression-'? --" );
                var formatted = referenceQuery();
                formatted.setColumnFormatter( ( column ) => column );
                var formattedCompiles = { "sizes": [] };
                observeCompiler( formatted, formattedCompiles );
                var formattedRows = referenceRows( 2 );
                var formattedResult = insertReferenceRows(
                    new megaphone.models.Storage.BulkRecords(),
                    formatted,
                    formattedRows,
                    {}
                );
                expect( formattedCompiles.sizes ).toBe( [ 2 ] );
                expect( variables.events.find( formattedResult[ 1 ][ 1 ].id ).eventKey ).toBe(
                    formattedRows[ 1 ].eventKey.value
                );
                var varied = referenceQuery();
                var variedCompiles = { "sizes": [] };
                observeCompiler( varied, variedCompiles );
                var variedRows = referenceRows( 2 );
                variedRows[ 2 ].version.cfsqltype = "bigint";
                var variedResult = insertReferenceRows(
                    new megaphone.models.Storage.BulkRecords(),
                    varied,
                    variedRows,
                    {}
                );
                expect( variedCompiles.sizes ).toBe( [ 2 ] );
                expect( variables.events.find( variedResult[ 2 ][ 1 ].id ).version ).toBe( 2 );
            } );
            it( "preserves a custom QueryUtils per-value normalizer through the full compiler fallback", () => {
                if ( !variables.fast ) {
                    var reference = variables.events.recordReferences( [ eventInput( createUUID() ) ] )[ 1 ];
                    expect( reference.created ).toBeTrue();
                    expect( variables.counter.count ).toBeGT( 0 );
                    return;
                }
                var query = referenceQuery();
                query.setUtils( new tests.resources.ReferenceNormalizingQueryUtils() );
                var rows = referenceRows( 3 );
                rows[ 1 ].payloadHash.value = "normalize:first";
                rows[ 2 ].payloadHash.value = "normalize:second";
                var compiles = { "sizes": [] };
                observeCompiler( query, compiles );
                var admitted = insertReferenceRows(
                    new megaphone.models.Storage.BulkRecords(),
                    query,
                    rows,
                    {}
                );
                expect( compiles.sizes ).toBe( [ 3 ] );
                expect( variables.events.find( admitted[ 1 ][ 1 ].id ).payloadHash ).toBe( "normalized:first" );
                expect( variables.events.find( admitted[ 2 ][ 1 ].id ).payloadHash ).toBe( "normalized:second" );
            } );
            it( "retains the generic insert and identity readback for a custom QueryBuilder subclass", () => {
                variables.injector
                    .getBinder()
                    .map( "QueryBuilder@qb", true )
                    .to( "tests.resources.CountingBulkQueryBuilder" )
                    .initArg( name = "grammar", value = variables.grammar )
                    .property( name = "compilationCounter", value = variables.counter );
                var query = variables.injector.getInstance( "QueryBuilder@qb" );
                expect( new megaphone.models.Storage.BulkRecords().supportsReturning( query ) ).toBeFalse();
                var reference = variables.events.recordReferences( [ eventInput( createUUID() ) ] )[ 1 ];
                expect( reference.created ).toBeTrue();
                expect( variables.counter.sql.len() ).toBeGT( 0 );
                expect( variables.events.find( reference.id ).payload.text ).toBe( "'quoted ?'" );
            } );
            it( "preserves caller dates and replay audit history with one stock reference audit clock", () => {
                var supplied = dateAdd( "l", 321, createDateTime( 2030, 3, 10, 9, 0, 0 ) );
                var old = dateAdd( "d", -30, now() );
                var input = eventInput( createUUID() );
                input.createdDate = supplied;
                // Retain fractional input while respecting the event column's database precision.
                var scalarInput = duplicate( input );
                scalarInput.namespace = createUUID();
                var expectedDate = variables.events.record( argumentCollection = scalarInput ).createdDate;
                if ( variables.isPostgres ) {
                    expect( millisecondsBetween( expectedDate, supplied ) ).toBe( 0 );
                }
                input.preparation = { "references": true, "auditClock": old };
                var event = variables.events.recordReferences( [ input ] )[ 1 ];
                expect( millisecondsBetween( variables.events.find( event.id ).createdDate, expectedDate ) ).toBe( 0 );
                expect( variables.events.recordReferences( [ input ] )[ 1 ].created ).toBeFalse();
                var intents = [];
                for ( var channel in [ "database", "email", "push" ] ) {
                    var item = deliveryInput( event.id );
                    item.channel = channel;
                    item.availableDate = supplied;
                    item.initialState = channel == "push" ? "suppressed" : "queued";
                    item.preparation = { "references": true, "auditClock": old };
                    intents.append( item );
                }
                var before = now();
                var references = variables.deliveries.enqueueReferences( intents );
                var after = now();
                var rows = references.map( ( item ) => variables.deliveries.find( item.id ) );
                for ( var row in rows ) {
                    expect( millisecondsBetween( row.availableDate, supplied ) ).toBe( 0 );
                    expect( dateCompare( row.createdDate, before ) >= 0 && dateCompare( row.createdDate, after ) <= 0 ).toBeTrue();
                    if ( variables.fast ) {
                        expect( millisecondsBetween( row.createdDate, rows[ 1 ].createdDate ) ).toBe( 0 );
                        expect( millisecondsBetween( row.updatedDate, rows[ 1 ].createdDate ) ).toBe( 0 );
                        if ( row.state == "suppressed" ) {
                            expect( millisecondsBetween( row.settledDate, rows[ 1 ].createdDate ) ).toBe( 0 );
                        }
                    }
                }
                var replay = variables.deliveries.enqueueReferences( intents );
                expect( replay.every( ( item ) => !item.created ) ).toBeTrue();
                for ( var index = 1; index <= replay.len(); index++ ) {
                    var stored = variables.deliveries.find( replay[ index ].id );
                    expect( millisecondsBetween( stored.createdDate, rows[ index ].createdDate ) ).toBe( 0 );
                    expect( millisecondsBetween( stored.updatedDate, rows[ index ].updatedDate ) ).toBe( 0 );
                }
                var full = duplicate( intents[ 1 ] );
                full.recipientId = createUUID();
                var fullWork = variables.deliveries.enqueueMany( [ full ] )[ 1 ];
                expect( dateCompare( fullWork.createdDate, before ) >= 0 ).toBeTrue();
                expect( millisecondsBetween( fullWork.availableDate, supplied ) ).toBe( 0 );
                var conflict = duplicate( intents[ 1 ] );
                conflict.routingHash = "different";
                expect( () => variables.deliveries.enqueueReferences( [ conflict ] ) ).toThrow( "Megaphone.Delivery.IdentityConflict" );
            } );
            it( "honors custom store overrides instead of bypassing their public batch methods", () => {
                var eventsCounter = { "count": 0 };
                var deliveryCounter = { "count": 0 };
                var eventReferences = variables.injector
                    .getInstance( "tests.resources.OverriddenReferenceEventStore" )
                    .setBatchCounter( eventsCounter );
                var deliveryReferences = variables.injector
                    .getInstance( "tests.resources.OverriddenReferenceDeliveryStore" )
                    .setBatchCounter( deliveryCounter );
                var event = eventReferences.recordReferences( [ eventInput( createUUID() ) ] )[ 1 ];
                var work = deliveryReferences.enqueueReferences( [ deliveryInput( event.id ) ] )[ 1 ];
                expect( eventsCounter.count ).toBe( 1 );
                expect( deliveryCounter.count ).toBe( 1 );
                expect( work.created ).toBeTrue();
            } );
            it( "keeps adapters that only implement the original batch store protocol", () => {
                var eventCounter = { "count": 0 };
                var deliveryCounter = { "count": 0 };
                variables.injector
                    .getBinder()
                    .map( "EventStore@megaphone" )
                    .toValue(
                        new tests.resources.LegacyBatchEventStore()
                            .setStore( variables.events )
                            .setBatchCounter( eventCounter )
                    );
                variables.injector
                    .getBinder()
                    .map( "DeliveryStore@megaphone" )
                    .toValue(
                        new tests.resources.LegacyBatchDeliveryStore()
                            .setStore( variables.deliveries )
                            .setBatchCounter( deliveryCounter )
                    );
                variables.service.admitRequests( [ notificationRequest( createUUID() ) ] );
                expect( eventCounter.count ).toBe( 1 );
                expect( deliveryCounter.count ).toBe( 1 );
                expect( variables.adapter.getReferences().len() ).toBe( 2 );
            } );
        } );
    }
    private any function referenceQuery() {
        return variables.injector.getInstance( "QueryBuilder@qb" ).from( "megaphone_events" );
    }
    private void function observeCompiler( required any query, required struct counter ) {
        arguments.query.megaphoneOriginalInsertIgnore = arguments.query.insertIgnore;
        var target = arguments.query;
        var counts = arguments.counter;
        arguments.query.insertIgnore = function() {
            counts.sizes.append( arguments.values.len() );
            return target.megaphoneOriginalInsertIgnore( argumentCollection = arguments );
        };
    }
    private array function referenceRows( required numeric count ) {
        var rows = [];
        var namespace = createUUID();
        for ( var index = 1; index <= arguments.count; index++ ) {
            rows.append( {
                "id": createObject( "java", "java.util.UUID" ).randomUUID().toString(),
                "namespace": namespace,
                "eventKey": "quote-'? OR true --" & index,
                "version": index,
                "type": "notice",
                "payloadHash": "hash-'? --" & index,
                "payload": serializeJSON( { "text": "'quoted ?' OR true --" & index } ),
                "createdDate": dateAdd( "l", index, createDateTime( 2026, 10, 15, 12, 13, 14 ) ),
                "notificationMapping": {
                    "value": index % 2 ? "" : "tests.resources.QueueNotification",
                    "null": index % 2 == 1,
                    "cfsqltype": "varchar"
                }
            } );
        }
        return new megaphone.models.Storage.BulkRecords().typedRows(
            rows,
            {
                "id": "varchar",
                "namespace": "varchar",
                "eventKey": "varchar",
                "version": "integer",
                "type": "varchar",
                "payloadHash": "varchar",
                "payload": "varchar",
                "createdDate": "timestamp"
            }
        );
    }
    private array function insertReferenceRows(
        required any bulk,
        required any query,
        required array rows,
        required struct templates
    ) {
        return arguments.bulk.insertReferences(
            query = arguments.query,
            values = arguments.rows,
            identities = arguments.rows.map( ( row ) => {
                return { "namespace": row.namespace, "eventKey": row.eventKey, "version": row.version };
            } ),
            columns = [ "id", "type", "payloadHash" ],
            queryFactory = () => referenceQuery(),
            tableName = "megaphone_events",
            templates = arguments.templates
        );
    }

    private struct function eventInput( required string key ) {
        return {
            "namespace": "references",
            "eventKey": arguments.key,
            "version": 1,
            "type": "notice",
            "payload": { "text": "'quoted ?'" },
            "payloadHash": "original"
        };
    }
    private struct function deliveryInput( required string id ) {
        return {
            "eventId": arguments.id,
            "recipientType": "User",
            "recipientId": "00012",
            "channel": "email",
            "deviceId": "",
            "routingData": { "text": "'quoted ?'" },
            "routingHash": "000123",
            "availableDate": dateAdd( "l", 123, createDateTime( 2026, 10, 15, 12, 13, 14 ) )
        };
    }
    private void function restoreStores() {
        variables.injector
            .getBinder()
            .map( "QueryBuilder@qb", true )
            .to( "qb.models.Query.QueryBuilder" )
            .initArg( name = "grammar", value = variables.grammar );
        variables.injector
            .getBinder()
            .map( "EventStore@megaphone" )
            .to( "megaphone.models.Storage.EventStore" );
        variables.injector
            .getBinder()
            .map( "DeliveryStore@megaphone" )
            .to( "megaphone.models.Storage.DeliveryStore" );
    }

    private numeric function millisecondsBetween( required date start, required date finish ) {
        return parseDateTime( arguments.finish ).getTime() - parseDateTime( arguments.start ).getTime();
    }

}
