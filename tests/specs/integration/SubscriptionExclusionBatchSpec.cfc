component extends="tests.specs.integration.SubscriptionStoreSpec" {

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
            it( "preserves request order, exact type identity, missing types and recipient ownership in one read", () => {
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
                variables.queries.clear();
                var types = [
                    "notice-'?--",
                    "missing",
                    "NOTICE-'?--",
                    "notice-'?--"
                ];
                var service = createMock( "megaphone.models.WebPush.PushSubscriptionService" ).$property(
                    "store",
                    "variables",
                    variables.subscriptions
                );
                var result = service.getExcludedIdsMany( variables.owner, types );
                expect( variables.queries.len() ).toBe( 1 );
                expect( find( "notice-'?--", variables.queries[ 1 ].sql ) ).toBe( 0 );
                expect( result ).toBe( [
                    [ first.id ],
                    [],
                    [ second.id ],
                    [ first.id ]
                ] );
                result[ 1 ].append( "modified" );
                expect( result[ 4 ] ).toBe( [ first.id ] );
                for ( var index = 1; index <= types.len(); index++ ) {
                    expect( service.getExcludedIdsMany( variables.owner, [ types[ index ] ] )[ 1 ] ).toBe(
                        service.getExcludedIds( variables.owner, types[ index ] )
                    );
                }
            } );
            it( "bounds unique types and executes no SQL for empty or invalid batches", () => {
                variables.queries.clear();
                expect( variables.subscriptions.excludedIdsMany( variables.owner, [] ) ).toBeEmpty();
                expect( variables.queries ).toBeEmpty();
                expect( () => variables.subscriptions.excludedIdsMany( variables.owner, [ "valid", "" ] ) ).toThrow(
                    type = "Megaphone.Push.InvalidExclusion"
                );
                expect( variables.queries ).toBeEmpty();
                var types = [];
                for ( var index = 1; index <= 501; index++ ) {
                    types.append( "type-" & index );
                }
                var result = variables.subscriptions.excludedIdsMany( variables.owner, types );
                expect( result.len() ).toBe( 501 );
                expect( variables.queries.len() ).toBe( 2 );
                expect( result.every( ( ids ) => ids.isEmpty() ) ).toBeTrue();
            } );
        } );
    }

}
