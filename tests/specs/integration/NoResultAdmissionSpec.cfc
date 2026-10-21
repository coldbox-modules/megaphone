/** Explicit no-result admission retains durable semantics without result model construction. */
component extends="tests.resources.BulkNotificationSpecBase" {

    function run() {
        describe( "No-result notification admission", () => {
            aroundEach( ( spec ) => {
                transaction {
                    try {
                        variables.owner = new tests.resources.InboxRecipient().setId( createUUID() );
                        variables.adapter = new tests.resources.BulkQueueFixture();
                        variables.config.queue.queueAdapter = variables.adapter;
                        variables.config.queue.snapshotHasher = "";
                        spec.body();
                    } finally {
                        transactionRollback();
                    }
                }
            } );
            it( "admits 101 plans as references without constructing public result models", () => {
                var adapter = new tests.resources.BulkReferenceQueueFixture();
                variables.config.queue.queueAdapter = adapter;
                var requests = [];
                for ( var index = 1; index <= 101; index++ ) {
                    requests.append( notificationRequest( createUUID() ) );
                }
                var plans = variables.service.planMany( requests );
                var binder = variables.injector.getBinder();
                var resultModels = [ "NotificationEvent", "NotificationDelivery", "NotificationPublication" ];
                for ( var name in resultModels ) {
                    binder.map( name & "@megaphone" ).to( "tests.resources.ResultModelConstructionGuard" );
                }
                try {
                    variables.service.admitPlans(
                        plans = plans,
                        connection = "reference-connection",
                        queue = "reference-queue"
                    );
                } finally {
                    restoreResultModels( resultModels );
                }
                expect( adapter.getReferences().len() ).toBe( 202 );
                expect( adapter.getDeliveries() ).toBeEmpty();
                expect( adapter.getReferenceOptions() ).toBe( [ { "connection": "reference-connection", "queue": "reference-queue" } ] );
                for ( var reference in adapter.getReferences() ) {
                    expect( reference.keyArray().sort( "text" ) ).toBe( [ "availableDate", "id", "state" ] );
                    expect( reference.state ).toBe( "queued" );
                    expect( dateCompare( reference.availableDate, requests[ 1 ].options.availableDate ) ).toBe( 0 );
                    var stored = variables.deliveries.find( reference.id );
                    expect( isDate( stored.createdDate ) ).toBeTrue();
                    expect( stored.attemptCount ).toBe( 0 );
                    expect( stored.transportCount ).toBe( 0 );
                }
                var first = variables.events.find(
                    variables.deliveries.find( adapter.getReferences()[ 1 ].id ).eventId
                );
                expect( variables.deliveries.forEvent( first.id ).len() ).toBe( 3 );
                expect(
                    variables.deliveries
                        .forEvent( first.id )
                        .filter( ( row ) => row.state == "suppressed" )
                        .len()
                ).toBe( 1 );
            } );
            it( "does not expand or enqueue a replayed no-result audience across duplicate chunks", () => {
                var adapter = new tests.resources.BulkReferenceQueueFixture();
                variables.config.queue.queueAdapter = adapter;
                var input = notificationRequest( createUUID() );
                var plans = variables.service.planMany( [ input ] );
                variables.service.admitPlans( plans );
                var first = variables.deliveries.find( adapter.getReferences()[ 1 ].id );
                input.notifiables = [ variables.owner, new tests.resources.InboxRecipient().setId( createUUID() ) ];
                var repeated = [];
                for ( var index = 1; index <= 101; index++ ) {
                    repeated.append( input );
                }
                variables.service.admitPlans( variables.service.planMany( repeated ) );
                expect( adapter.getReferences().len() ).toBe( 2 );
                expect( variables.deliveries.forEvent( first.eventId ).len() ).toBe( 3 );
                expect(
                    variables.deliveries
                        .forEvent( first.eventId )
                        .filter( ( row ) => row.state == "suppressed" )
                        .len()
                ).toBe( 1 );
            } );
            it( "preserves admission cutoffs and the explicit already-admitted override", () => {
                var adapter = new tests.resources.BulkReferenceQueueFixture();
                variables.config.queue.queueAdapter = adapter;
                var input = notificationRequest( createUUID() );
                var plan = variables.service.plan( argumentCollection = input );
                var captured = plan.getMemento();
                captured.admitAfter = dateAdd( "d", 1, captured.event.createdDate );
                plan.populateFromMemento( captured );
                variables.service.admitPlans( [ plan ] );
                expect( adapter.getReferences() ).toBeEmpty();
                variables.service.admitPlans( plans = [ plan ], alreadyAdmitted = true );
                expect( adapter.getReferences().len() ).toBe( 2 );
            } );
            it( "rolls back no-result admission when a reference queue insertion fails", () => {
                var adapter = new tests.resources.BulkReferenceQueueFixture( true );
                variables.config.queue.queueAdapter = adapter;
                var plans = variables.service.planMany( [ notificationRequest( createUUID() ), notificationRequest( createUUID() ) ] );
                expect( () => variables.service.admitPlans( plans ) ).toThrow( "QueueFixtureUnavailable" );
                expect( isNull( variables.deliveries.find( adapter.getReferences()[ 1 ].id ) ) ).toBeTrue();
                expect(
                    variables.injector
                        .getInstance( "QueryBuilder@qb" )
                        .from( "megaphone_events" )
                        .where( "eventKey", plans[ 1 ].getEvent().eventKey )
                        .count()
                ).toBe( 0 );
            } );
            it( "rolls back earlier no-result work on a conflicting immutable event", () => {
                var adapter = new tests.resources.BulkReferenceQueueFixture();
                variables.config.queue.queueAdapter = adapter;
                var input = notificationRequest( createUUID() );
                variables.service.admitPlans( variables.service.planMany( [ input ] ) );
                var fresh = notificationRequest( createUUID() );
                input.properties.message = "conflicting payload";
                expect( () => variables.service.admitPlans( variables.service.planMany( [ fresh, input ] ) ) ).toThrow( "Megaphone.Events.IdentityConflict" );
                expect(
                    variables.injector
                        .getInstance( "QueryBuilder@qb" )
                        .from( "megaphone_events" )
                        .whereIn( "eventKey", [ fresh.options.eventKey, input.options.eventKey ] )
                        .count()
                ).toBe( 0 );
                expect( isNull( variables.deliveries.find( adapter.getReferences()[ 1 ].id ) ) ).toBeTrue();
            } );
            it( "retains typed legacy adapter admission when the reference capability is absent", () => {
                var legacy = new tests.resources.DurableQueueFixture();
                variables.config.queue.queueAdapter = legacy;
                var plans = variables.service.planMany( [ notificationRequest( createUUID() ) ] );
                variables.service.admitPlans( plans );
                variables.service.admitPlans( plans );
                expect( legacy.getDeliveries().len() ).toBe( 2 );
                expect( variables.deliveries.forEvent( legacy.getDeliveries()[ 1 ].eventId ).len() ).toBe( 3 );
            } );
        } );
    }

    private void function restoreResultModels( required array names ) {
        for ( var name in arguments.names ) {
            variables.injector
                .getBinder()
                .map( name & "@megaphone" )
                .to( "megaphone.models.Delivery." & name );
        }
    }

}
