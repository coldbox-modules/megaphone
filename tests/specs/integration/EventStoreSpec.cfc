component extends="tests.specs.integration.DatabaseInboxSpec" {

    function beforeAll() {
        super.beforeAll();
        variables.injector
            .getBinder()
            .map( "EventStore@megaphone" )
            .to( "megaphone.models.EventStore" );
        variables.events = variables.injector.getInstance( "EventStore@megaphone" );
    }

    function run() {
        describe( "Durable event identity", () => {
            aroundEach( ( spec ) => {
                transaction {
                    try {
                        spec.body();
                    } finally {
                        transactionRollback();
                    }
                }
            } );
            it( "reuses an identical event independently of inbox retention", () => {
                var key = createUUID();
                var first = record( key );
                var repeated = record( key );
                expect( repeated.id ).toBe( first.id );
                expect( repeated.payload.message ).toBe( "Original" );
                var revised = record( key, 2 );
                expect( revised.id ).notToBe( first.id );
                expect( variables.events.find( first.id ).payloadHash ).toBe( "original-hash" );
            } );
            it( "rejects identity reuse with changed content", () => {
                var key = createUUID();
                record( key );
                expect( function() {
                    return variables.events.record(
                        namespace = "test",
                        eventKey = key,
                        version = 1,
                        type = "submitted",
                        payload = { "message": "Changed" },
                        payloadHash = "different-hash"
                    );
                } ).toThrow( type = "Megaphone.Events.IdentityConflict" );
            } );
            it( "rolls back event identity with the domain transaction", () => {
                var event = record( createUUID() );
                transactionRollback();
                expect( isNull( variables.events.find( event.id ) ) ).toBeTrue();
            } );
            it( "rejects missing identities and invalid versions before storage", () => {
                expect( function() {
                    return record( "", 1 );
                } ).toThrow( type = "Megaphone.Events.InvalidIdentity" );
                expect( function() {
                    return record( createUUID(), 0 );
                } ).toThrow( type = "Megaphone.Events.InvalidIdentity" );
            } );
        } );
    }

    private struct function record( required string key, numeric version = 1 ) {
        return variables.events.record(
            namespace = "test",
            eventKey = arguments.key,
            version = arguments.version,
            type = "submitted",
            payload = { "message": "Original" },
            payloadHash = "original-hash"
        );
    }

}
