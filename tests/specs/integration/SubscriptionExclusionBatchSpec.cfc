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
            it( "matches scalar database comparisons while preserving order, missing types and recipient ownership in one read", () => {
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
                expect( result ).toBe( expected );
                expect( result[ 1 ].contains( foreign.id ) ).toBeFalse();
                expect( result[ 1 ].contains( differentDevice.id ) ).toBeFalse();
                result[ 1 ].append( "modified" );
                expect( result[ 4 ] ).toBe( expected[ 4 ] );
                for ( var index = 1; index <= types.len(); index++ ) {
                    expect( variables.push.getExcludedIdsForTypes( variables.owner, [ types[ index ] ] )[ 1 ] ).toBe(
                        variables.push.getExcludedIds( variables.owner, types[ index ] )
                    );
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
                    types.append( "type-" & index );
                }
                var result = variables.subscriptions.excludedIdsForTypes( variables.owner, types );
                expect( result.len() ).toBe( 101 );
                expect( variables.queries.len() ).toBe( 2 );
                expect( result.every( ( ids ) => ids.isEmpty() ) ).toBeTrue();
            } );
        } );
    }

}
