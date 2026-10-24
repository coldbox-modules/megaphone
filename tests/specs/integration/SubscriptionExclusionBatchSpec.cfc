component extends="tests.specs.integration.SubscriptionStoreSpec" {

    function beforeAll() {
        super.beforeAll();
        variables.injector
            .getBinder()
            .map( "PushSubscriptionService@megaphone" )
            .to( "megaphone.models.WebPush.PushSubscriptionService" );
        variables.push = variables.injector.getInstance( "PushSubscriptionService@megaphone" );
    }

    function run() {
        describe( "Batched owned device exclusions", () => {
            aroundEach( ( spec ) => {
                transaction {
                    var previous = variables.grammar.getInterceptorService();
                    try {
                        variables.owner = new tests.resources.InboxRecipient( id = "batch-owner", type = "User" );
                        variables.other = new tests.resources.InboxRecipient( id = "batch-owner", type = "Team" );
                        variables.queries = [];
                        variables.grammar.setInterceptorService(
                            new tests.resources.PreferenceQueryObserver()
                                .setDelegate( previous )
                                .setQueries( variables.queries )
                        );
                        spec.body();
                    } finally {
                        transactionRollback();
                        variables.grammar.setInterceptorService( previous );
                    }
                }
            } );
            it( "returns type-keyed exclusions matching scalar database comparisons and recipient ownership in one read", () => {
                var first = register( variables.owner, "batch-first" );
                var second = register( variables.owner, "batch-second" );
                var foreign = register( variables.other, "batch-other" );
                variables.subscriptions.setExcluded(
                    variables.owner,
                    "notice-'?--",
                    first.id,
                    true
                );
                variables.subscriptions.setExcluded(
                    variables.owner,
                    "NOTICE-'?--",
                    second.id,
                    true
                );
                variables.subscriptions.setExcluded(
                    variables.other,
                    "notice-'?--",
                    foreign.id,
                    true
                );
                var differentOwner = new tests.resources.InboxRecipient( id = "another-owner", type = "User" );
                var differentDevice = register( differentOwner, "different-owner" );
                variables.subscriptions.setExcluded(
                    differentOwner,
                    "notice-'?--",
                    differentDevice.id,
                    true
                );
                var types = [
                    "notice-'?--",
                    "missing",
                    "NOTICE-'?--",
                    "notice-'?--"
                ];
                var expected = types.map( ( type ) => variables.subscriptions.excludedIds( variables.owner, type ) );
                variables.queries.clear();
                var result = variables.push.getExcludedIdsForTypes( variables.owner, types );
                expect( variables.queries.len() ).toBe( 1 );
                expect( find( "notice-'?--", variables.queries[ 1 ].sql ) ).toBe( 0 );
                expect( isStruct( result ) ).toBeTrue();
                expect( structCount( result ) ).toBe( 3 );
                var serialized = serializeJSON( result );
                expect( find( serializeJSON( types[ 1 ] ), serialized ) > 0 ).toBeTrue();
                expect( find( serializeJSON( types[ 3 ] ), serialized ) > 0 ).toBeTrue();
                for ( var index = 1; index <= types.len(); index++ ) {
                    expect( result[ types[ index ] ] ).toBe( expected[ index ] );
                }
                expect( result[ types[ 1 ] ].contains( foreign.id ) ).toBeFalse();
                expect( result[ types[ 1 ] ].contains( differentDevice.id ) ).toBeFalse();
                result[ types[ 1 ] ].append( "modified" );
                expect( result[ types[ 3 ] ] ).toBe( expected[ 3 ] );
                for ( var index = 1; index <= types.len(); index++ ) {
                    expect(
                        variables.push.getExcludedIdsForTypes( variables.owner, [ types[ index ] ] )[ types[ index ] ]
                    ).toBe( variables.push.getExcludedIds( variables.owner, types[ index ] ) );
                }
            } );
            it( "bounds requests and executes no SQL for empty or invalid batches", () => {
                variables.queries.clear();
                expect( variables.subscriptions.excludedIdsForTypes( variables.owner, [] ) ).toBeEmpty();
                expect( variables.queries ).toBeEmpty();
                expect( () => variables.subscriptions.excludedIdsForTypes( variables.owner, [ "valid", "" ] ) ).toThrow(
                    type = "Megaphone.Push.InvalidExclusion"
                );
                expect( variables.queries ).toBeEmpty();
                expect( () => variables.subscriptions.excludedIdsForTypes( variables.owner, [ {} ] ) ).toThrow(
                    type = "Megaphone.Push.InvalidExclusion"
                );
                expect( () => variables.subscriptions.excludedIdsForTypes( variables.owner, [ repeatString( "x", 161 ) ] ) ).toThrow(
                    type = "Megaphone.Push.InvalidExclusion"
                );
                expect( variables.queries ).toBeEmpty();
                var types = [];
                for ( var index = 1; index <= 101; index++ ) {
                    types.append( index == 1 ? "containsKey" : "type-" & index );
                }
                var result = variables.subscriptions.excludedIdsForTypes( variables.owner, types );
                expect( structCount( result ) ).toBe( 101 );
                expect( variables.queries.len() ).toBe( 2 );
                for ( var type in result ) {
                    expect( result[ type ] ).toBeEmpty();
                }
                variables.queries.clear();
                var repeated = [];
                for ( var index = 1; index <= 101; index++ ) {
                    repeated.append( "put" );
                }
                expect( structCount( variables.push.getExcludedIdsForTypes( variables.owner, repeated ) ) ).toBe( 1 );
                expect( variables.queries.len() ).toBe( 1 );
            } );
        } );
    }

}
