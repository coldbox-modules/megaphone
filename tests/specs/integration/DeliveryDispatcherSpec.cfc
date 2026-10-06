component extends="tests.specs.integration.DeliveryStoreSpec" {

    function beforeAll() {
        super.beforeAll();
        variables.injector
            .getBinder()
            .map( "DeliveryDispatcher@megaphone" )
            .to( "megaphone.models.DeliveryDispatcher" );
        variables.dispatcher = variables.injector.getInstance( "DeliveryDispatcher@megaphone" );
    }
    function run() {
        describe( "Dispatch-time policy and transport boundary", () => {
            aroundEach( ( spec ) => {
                transaction {
                    try {
                        var event = variables.events.record(
                            namespace = "test",
                            eventKey = createUUID(),
                            version = 1,
                            type = "submitted",
                            payload = {},
                            payloadHash = "snapshot"
                        );
                        variables.work = variables.deliveries.enqueue(
                            eventId = event.id,
                            recipientType = "User",
                            recipientId = "recipient",
                            channel = "email",
                            routingData = {},
                            routingHash = "routing"
                        );
                        variables.sends = 0;
                        spec.body();
                    } finally {
                        transactionRollback();
                    }
                }
            } );
            it( "rechecks preferences and access before sending", () => {
                var result = variables.dispatcher.dispatch(
                    id = variables.work.id,
                    eligibility = ( delivery ) => {
                        return { "status": "suppressed", "reason": "access-revoked" };
                    },
                    sender = ( delivery, ready ) => accepted()
                );
                expect( result ).toBe( "suppressed" );
                expect( variables.sends ).toBe( 0 );
                expect( variables.deliveries.find( variables.work.id ).transportCount ).toBe( 0 );
            } );
            it( "delivers once and persists acceptance without interpreting it as read", () => {
                expect( dispatchAccepted() ).toBe( "accepted" );
                expect( dispatchAccepted() ).toBe( "accepted" );
                expect( variables.sends ).toBe( 1 );
                expect( variables.deliveries.find( variables.work.id ).providerReference ).toBe( "receipt" );
                expect( variables.deliveries.find( variables.work.id ).transportCount ).toBe( 1 );
            } );
            it( "does not exhaust transport attempts while an application feature is paused", () => {
                for ( var execution = 1; execution <= 6; execution++ ) {
                    expect(
                        variables.dispatcher.dispatch(
                            id = variables.work.id,
                            eligibility = ( delivery ) => {
                                return { "status": "deferred", "reason": "feature-paused", "retryDate": now() };
                            },
                            sender = ( delivery, ready ) => accepted(),
                            maxAttempts = 1
                        )
                    ).toBe( "retryable" );
                }
                expect( variables.sends ).toBe( 0 );
                expect( variables.deliveries.find( variables.work.id ).transportCount ).toBe( 0 );
                expect( dispatchAccepted() ).toBe( "accepted" );
            } );
            it( "makes provider exceptions ambiguous and prevents automatic replay", () => {
                var result = variables.dispatcher.dispatch(
                    id = variables.work.id,
                    eligibility = ( delivery ) => {
                        return { "status": "ready" };
                    },
                    sender = ( delivery, ready ) => {
                        variables.sends++;
                        throw( message = "Transport disconnected after acceptance may have happened." );
                    }
                );
                expect( result ).toBe( "ambiguous" );
                expect( dispatchAccepted() ).toBe( "ambiguous" );
                expect( variables.sends ).toBe( 1 );
                expect( variables.deliveries.find( variables.work.id ).reason ).toBe( "provider-outcome-unknown" );
            } );
            it( "retries pre-transport preparation failures without assuming a send", () => {
                var result = variables.dispatcher.dispatch(
                    id = variables.work.id,
                    eligibility = ( delivery ) => {
                        throw( message = "Preparation failed." );
                    },
                    sender = ( delivery, ready ) => accepted()
                );
                expect( result ).toBe( "retryable" );
                expect( variables.sends ).toBe( 0 );
                expect( variables.deliveries.find( variables.work.id ).reason ).toBe( "eligibility-error" );
                expect( variables.deliveries.find( variables.work.id ).transportCount ).toBe( 0 );
            } );
            it( "does not send after eligibility invalidates the worker lease", () => {
                var result = variables.dispatcher.dispatch(
                    id = variables.work.id,
                    eligibility = ( delivery ) => {
                        variables.deliveries.recoverExpired( clock = dateAdd( "s", 120, now() ) );
                        return { "status": "ready" };
                    },
                    sender = ( delivery, ready ) => accepted()
                );
                expect( result ).toBe( "superseded" );
                expect( variables.sends ).toBe( 0 );
            } );
        } );
    }
    private string function dispatchAccepted() {
        return variables.dispatcher.dispatch(
            id = variables.work.id,
            eligibility = ( delivery ) => {
                return { "status": "ready" };
            },
            sender = ( delivery, ready ) => accepted()
        );
    }
    private struct function accepted() {
        variables.sends++;
        return { "outcome": "accepted", "providerReference": "receipt" };
    }

}
