component extends="tests.specs.integration.PreferenceStoreSpec" {

    function run() {
        describe( "Bounded preference identities", () => {
            aroundEach( ( spec ) => {
                transaction {
                    var previous = variables.grammar.getInterceptorService();
                    try {
                        variables.queries = [];
                        variables.grammar.setInterceptorService(
                            new tests.resources.PreferenceQueryObserver()
                                .setDelegate( previous )
                                .setQueries( variables.queries )
                        );
                        variables.owner = new tests.resources.InboxRecipient( id = "00001", type = "lookup-'?--" );
                        spec.body();
                    } finally {
                        transactionRollback();
                        variables.grammar.setInterceptorService( previous );
                    }
                }
            } );
            it( "preserves duplicate ordinals and multi-scope ordering across the 1000 boundary", () => {
                var notificationType = "notice-' OR true -- ?";
                var scopes = [ "account", "org-'?--" ];
                variables.preferences.saveChoice(
                    variables.owner,
                    notificationType,
                    scopes[ 1 ],
                    "email",
                    "on"
                );
                variables.preferences.saveChoice(
                    variables.owner,
                    notificationType,
                    scopes[ 2 ],
                    "email",
                    "off"
                );
                variables.queries.clear();
                var inputs = [];
                for ( var index = 1; index <= 1001; index++ ) {
                    inputs.append( {
                        "notifiable": variables.owner,
                        "notificationType": notificationType,
                        "scopeKeys": [ scopes[ 2 ], scopes[ 1 ], scopes[ 2 ] ]
                    } );
                }
                inputs.append( {
                    "notifiable": new tests.resources.InboxRecipient( id = "1", type = variables.owner.getType() ),
                    "notificationType": notificationType,
                    "scopeKeys": scopes
                } );
                inputs.append( { "notifiable": variables.owner, "notificationType": notificationType, "scopeKeys": [] } );
                var results = variables.preferences.choicesMany( inputs );
                expect( results.len() ).toBe( 1003 );
                for ( var index = 1; index <= 1001; index++ ) {
                    expect( results[ index ] ).toBe( [
                        { "key": scopes[ 2 ], "choices": { "email": "off" } },
                        { "key": scopes[ 1 ], "choices": { "email": "on" } },
                        { "key": scopes[ 2 ], "choices": { "email": "off" } }
                    ] );
                }
                expect( results[ 1002 ][ 1 ].choices ).toBeEmpty();
                expect( results[ 1003 ] ).toBeEmpty();
                var fast = application.megaphoneRequireReturning ?: false;
                var jsonQueries = variables.queries.filter( ( item ) => findNoCase( "JSONB_TO_RECORDSET", item.sql ) > 0 );
                expect( jsonQueries.len() ).toBe( fast ? 2 : 0 );
                for ( var item in jsonQueries ) {
                    expect( item.bindings.len() ).toBe( 1 );
                    expect( find( notificationType, item.sql ) ).toBe( 0 );
                }
            } );
            it( "retains a custom builder and its original one-factory-per-100 lookup lifecycle", () => {
                variables.preferences.saveChoice(
                    variables.owner,
                    "notice",
                    "account",
                    "email",
                    "on"
                );
                variables.injector
                    .getBinder()
                    .map( "PreferenceCountingQuery" )
                    .to( "tests.resources.CountingBulkQueryBuilder" )
                    .initArg( name = "grammar", value = variables.grammar );
                var calls = { "factory": 0, "count": 0 };
                var identities = [];
                for ( var index = 1; index <= 101; index++ ) {
                    identities.append( {
                        "recipientType": variables.owner.getType(),
                        "recipientId": variables.owner.getId(),
                        "notificationType": "notice",
                        "scopeKey": [ "account" ]
                    } );
                }
                variables.queries.clear();
                var result = new megaphone.models.Storage.BulkRecords().readPreferences(
                    store = variables.preferences,
                    queryFactory = () => {
                        calls.factory++;
                        return variables.injector
                            .getInstance( "PreferenceCountingQuery" )
                            .setCompilationCounter( calls );
                    },
                    identities = identities,
                    tableName = variables.preferences.getTableName(),
                    queryOptions = variables.preferences.getQueryOptions()
                );
                expect( calls.factory ).toBe( 2 );
                expect( calls.count ).toBe( 4 );
                expect( result.len() ).toBe( 101 );
                for ( var rows in result ) {
                    expect( rows.len() ).toBe( 1 );
                    expect( rows[ 1 ].choice ).toBe( "on" );
                }
                expect( variables.queries.filter( ( item ) => findNoCase( "JSONB_TO_RECORDSET", item.sql ) > 0 ) ).toBeEmpty();
            } );
            it( "keeps custom stores on the original typed lookup and rejects empty keys before querying", () => {
                var custom = variables.injector.getInstance( "tests.resources.CustomPreferenceStore" );
                custom.saveChoice(
                    variables.owner,
                    "notice",
                    "account",
                    "email",
                    "on"
                );
                variables.queries.clear();
                var result = custom.choicesMany( [
                    {
                        "notifiable": variables.owner,
                        "notificationType": "notice",
                        "scopeKeys": [ "account", "account" ]
                    }
                ] );
                expect( result[ 1 ][ 1 ].choices.email ).toBe( "on" );
                expect( result[ 1 ][ 2 ] ).toBe( result[ 1 ][ 1 ] );
                expect( variables.queries.filter( ( item ) => findNoCase( "JSONB_TO_RECORDSET", item.sql ) > 0 ) ).toBeEmpty();
                var count = variables.queries.len();
                expect( () => variables.preferences.choicesMany( [ { "notifiable": variables.owner, "notificationType": "notice", "scopeKeys": [ "" ] } ] ) ).toThrow( "Megaphone.Preferences.InvalidKey" );
                expect( variables.queries.len() ).toBe( count );
            } );
        } );
    }

}
