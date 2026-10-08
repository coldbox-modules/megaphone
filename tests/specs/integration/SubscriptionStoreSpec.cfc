component extends="tests.specs.integration.DatabaseInboxSpec" {

    function beforeAll() {
        super.beforeAll();
        variables.injector
            .getBinder()
            .map( "SubscriptionStore@megaphone" )
            .to( "megaphone.models.SubscriptionStore" );
        variables.subscriptions = variables.injector.getInstance( "SubscriptionStore@megaphone" );
        variables.resolver = new megaphone.models.PreferenceResolver();
    }
    function run() {
        describe( "Owned browser push destinations", () => {
            aroundEach( ( spec ) => {
                transaction {
                    try {
                        variables.owner = new tests.resources.InboxRecipient();
                        variables.other = new tests.resources.InboxRecipient();
                        spec.body();
                    } finally {
                        transactionRollback();
                    }
                }
            } );
            it( "deduplicates registrations and does not expose subscription material in device lists", () => {
                var first = register( variables.owner, "endpoint" );
                var repeated = register( variables.owner, "endpoint" );
                expect( repeated.id ).toBe( first.id );
                expect( variables.subscriptions.registrations( variables.owner ).len() ).toBe( 1 );
                var data = serializeJSON( first );
                expect( data ).notToInclude( "sealedData" );
                expect( data ).notToInclude( "endpointHash" );
                expect( variables.subscriptions.registrations( variables.other ).len() ).toBe( 0 );
            } );
            it( "preserves stable identity and exclusions through subscription renewal", () => {
                var first = register( variables.owner, "original" );
                variables.subscriptions.setExcluded(
                    variables.owner,
                    "submitted",
                    first.id,
                    true
                );
                var renewed = variables.subscriptions.register(
                    notifiable = variables.owner,
                    endpointHash = hash( "renewed", "SHA-256" ),
                    sealedData = "sealed-renewed",
                    existingId = first.id
                );
                expect( renewed.id ).toBe( first.id );
                expect( renewed.label ).toBe( first.label );
                expect( variables.subscriptions.excludedIds( variables.owner, "submitted" ) ).toBe( [ first.id ] );
                expect( variables.subscriptions.activeRegistration( variables.owner, first.id ).sealedData ).toBe( "sealed-renewed" );
                expect( variables.subscriptions.registrations( variables.owner ).len() ).toBe( 1 );
            } );
            it( "includes later registrations while honoring only the intended type's exclusions", () => {
                var first = register( variables.owner, "first" );
                variables.subscriptions.setExcluded(
                    variables.owner,
                    "submitted",
                    first.id,
                    true
                );
                var future = register( variables.owner, "future" );
                var registrations = variables.subscriptions.registrations( variables.owner );
                var selected = variables.resolver.selectDevices(
                    registrations,
                    variables.subscriptions.excludedIds( variables.owner, "submitted" )
                );
                expect( selected.len() ).toBe( 1 );
                expect( selected[ 1 ].id ).toBe( future.id );
                expect(
                    variables.resolver
                        .selectDevices( registrations, variables.subscriptions.excludedIds( variables.owner, "offer" ) )
                        .len()
                ).toBe( 2 );
                variables.subscriptions.setExcluded(
                    variables.owner,
                    "submitted",
                    first.id,
                    false
                );
                expect( variables.subscriptions.excludedIds( variables.owner, "submitted" ).len() ).toBe( 0 );
            } );
            it( "moves a shared endpoint to a new owned identity without preserving the previous account's previews", () => {
                var first = register( variables.owner, "shared" );
                variables.subscriptions.setExcluded(
                    variables.owner,
                    "submitted",
                    first.id,
                    true
                );
                var switched = register( variables.other, "shared" );
                expect( switched.id ).notToBe( first.id );
                expect( isNull( variables.subscriptions.activeRegistration( variables.owner, first.id ) ) ).toBeTrue();
                expect( variables.subscriptions.registrations( variables.owner ).len() ).toBe( 0 );
                expect( variables.subscriptions.activeRegistration( variables.other, switched.id ).sealedData ).toBe( "sealed-shared" );
                expect( variables.subscriptions.excludedIds( variables.other, "submitted" ).len() ).toBe( 0 );
            } );
            it( "rejects foreign renewal exclusion rename and disconnect requests", () => {
                var first = register( variables.owner, "private" );
                expect( variables.subscriptions.rename( variables.other, first.id, "Taken" ) ).toBeFalse();
                expect( variables.subscriptions.disconnect( variables.other, first.id ) ).toBeFalse();
                expect( function() {
                    return variables.subscriptions.setExcluded(
                        variables.other,
                        "submitted",
                        first.id,
                        true
                    );
                } ).toThrow( type = "Megaphone.Push.UnknownRegistration" );
                expect( function() {
                    return variables.subscriptions.register(
                        notifiable = variables.other,
                        endpointHash = hash( "foreign", "SHA-256" ),
                        sealedData = "sealed",
                        label = "Foreign",
                        existingId = first.id
                    );
                } ).toThrow( type = "Megaphone.Push.UnknownRegistration" );
            } );
            it( "retires credentials on disconnect and does not serve expired destinations", () => {
                var first = register( variables.owner, "first" );
                expect( variables.subscriptions.disconnect( variables.owner, first.id ) ).toBeTrue();
                expect( variables.subscriptions.disconnect( variables.owner, first.id ) ).toBeTrue();
                expect( isNull( variables.subscriptions.activeRegistration( variables.owner, first.id ) ) ).toBeTrue();
                var retired = new qb.models.Query.QueryBuilder( grammar = variables.grammar )
                    .from( "megaphone_subscriptions" )
                    .where( "id", first.id )
                    .get()[ 1 ];
                expect( retired.sealedData ).toBe( "" );
                var expired = variables.subscriptions.register(
                    notifiable = variables.owner,
                    endpointHash = hash( "expired", "SHA-256" ),
                    sealedData = "sealed",
                    label = "Expired",
                    expiresDate = dateAdd( "d", -1, now() )
                );
                expect( isNull( variables.subscriptions.activeRegistration( variables.owner, expired.id ) ) ).toBeTrue();
                expect( variables.subscriptions.registrations( variables.owner ).len() ).toBe( 0 );
                expect( variables.subscriptions.registrations( variables.owner, false ).len() ).toBe( 2 );
            } );
            it( "prunes inactive registrations in bounded batches without deleting active devices", () => {
                var first = register( variables.owner, "first" );
                variables.subscriptions.setExcluded(
                    variables.owner,
                    "submitted",
                    first.id,
                    true
                );
                variables.subscriptions.disconnect( variables.owner, first.id );
                var active = register( variables.other, "active" );
                expect( variables.subscriptions.pruneInactive( beforeDate = dateAdd( "d", 1, now() ), limit = 1 ) ).toBe(
                    1
                );
                expect( variables.subscriptions.excludedIds( variables.owner, "submitted" ).len() ).toBe( 0 );
                expect( variables.subscriptions.registrations( variables.other )[ 1 ].id ).toBe( active.id );
                expect( variables.subscriptions.pruneInactive( beforeDate = dateAdd( "d", 1, now() ) ) ).toBe( 0 );
            } );
        } );
    }
    private struct function register( required any owner, required string key ) {
        return variables.subscriptions.register(
            notifiable = arguments.owner,
            endpointHash = hash( arguments.key, "SHA-256" ),
            sealedData = "sealed-" & arguments.key,
            label = "Browser"
        );
    }

}
