component extends="tests.specs.integration.EventStoreSpec" {

    function run() {
        describe( "Typed bulk identity templates", () => {
            aroundEach( ( spec ) => {
                transaction {
                    try {
                        variables.namespace = "typed-template:" & createUUID();
                        variables.counter = { "count": 0 };
                        variables.injector
                            .getBinder()
                            .map( "CountingBulkQueryBuilder" )
                            .to( "tests.resources.CountingBulkQueryBuilder" )
                            .initArg( name = "grammar", value = variables.grammar );
                        spec.body();
                    } finally {
                        transactionRollback();
                    }
                }
            } );
            it( "compiles one typed shape per chunk and substitutes only bound values", () => {
                var first = record( "First-'?-", 1 );
                var second = record( "Second-' OR true --", 2 );
                var identities = [];
                for ( var index = 1; index <= 101; index++ ) {
                    var item = index % 2 ? first : second;
                    identities.append( identity( item.eventKey, binding( item.version, "integer" ) ) );
                }
                var rows = read( identities );
                expect( variables.counter.count ).toBe( 4 );
                for ( var index = 1; index <= rows.len(); index++ ) {
                    expect( rows[ index ].len() ).toBe( 1 );
                    expect( rows[ index ][ 1 ].id ).toBe( index % 2 ? first.id : second.id );
                }
            } );
            it( "separates SQL types, nulls, metadata and IN cardinalities while retaining raw-input fallback", () => {
                var first = record( "First-'?-", 1 );
                var second = record( "Second-' OR true --", 2 );
                var third = record( "Third-' OR 1=1 -- ?", 1 );
                var scalar = identity( first.eventKey, binding( 1, "integer" ) );
                var other = identity( second.eventKey, binding( 2, "integer" ) );
                var wide = identity( first.eventKey, binding( 1, "bigint" ) );
                var one = identity( [ binding( first.eventKey, "varchar" ) ], binding( 1, "integer" ) );
                var two = identity(
                    [ binding( first.eventKey, "varchar" ), binding( third.eventKey, "varchar" ) ],
                    binding( 1, "integer" )
                );
                var empty = identity( [], binding( 1, "integer" ) );
                var absent = identity( first.eventKey, binding( 1, "integer" ) );
                absent.eventKey[ "null" ] = true;
                var metadata = identity( first.eventKey, binding( 1, "integer" ) );
                metadata.eventKey[ "maxlength" ] = 190;
                var raw = { "namespace": variables.namespace, "eventKey": third.eventKey, "version": 1 };
                var rows = read( [
                    scalar,
                    other,
                    wide,
                    one,
                    two,
                    empty,
                    duplicate( empty ),
                    absent,
                    metadata,
                    raw
                ] );
                expect( variables.counter.count ).toBe( 9 );
                expect( rows.map( ( items ) => items.len() ) ).toBe( [ 1, 1, 1, 1, 2, 0, 0, 0, 1, 1 ] );
                expect( rows[ 2 ][ 1 ].id ).toBe( second.id );
                expect( rows[ 3 ][ 1 ].id ).toBe( first.id );
                expect( rows[ 10 ][ 1 ].id ).toBe( third.id );
                expect( rows[ 5 ].map( ( row ) => row.id ).sort( "text" ) ).toBe( [ first.id, third.id ].sort( "text" ) );
            } );
        } );
    }
    private struct function record( required string key, required numeric version ) {
        return variables.events.record(
            namespace = variables.namespace,
            eventKey = arguments.key & createUUID(),
            version = arguments.version,
            type = "notice",
            payload = {},
            payloadHash = "frozen"
        );
    }
    private struct function binding( required any value, required string type ) {
        return {
            "value": arguments.value,
            "cfsqltype": arguments.type,
            "null": false,
            "list": false
        };
    }
    private struct function identity( required any key, required struct version ) {
        return {
            "namespace": binding( variables.namespace, "varchar" ),
            "eventKey": isArray( arguments.key ) ? arguments.key : binding( arguments.key, "varchar" ),
            "version": arguments.version
        };
    }
    private array function read( required array identities ) {
        return new megaphone.models.Storage.BulkRecords().read(
            queryFactory = () => variables.injector
                .getInstance( "CountingBulkQueryBuilder" )
                .setCompilationCounter( variables.counter )
                .from( "megaphone_events" ),
            identities = arguments.identities,
            tableName = "megaphone_events"
        );
    }

}
