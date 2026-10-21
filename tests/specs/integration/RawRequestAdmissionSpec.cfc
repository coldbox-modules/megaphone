/** Opt-in request admission preserves the mapped-plan fallback and durable boundaries. */
component extends="tests.resources.BulkNotificationSpecBase" {

    function run() {
        describe( "No-result request admission", () => {
            aroundEach( ( spec ) => {
                transaction {
                    try {
                        variables.owner = new tests.resources.InboxRecipient().setId( createUUID() );
                        variables.adapter = new tests.resources.BulkReferenceQueueFixture();
                        variables.config.queue.queueAdapter = variables.adapter;
                        variables.config.queue.snapshotHasher = "";
                        spec.body();
                    } finally {
                        transactionRollback();
                        restoreModels();
                        var channel = variables.injector.getInstance( "DatabaseProvider@megaphone" );
                        variables.service.setChannels( { "database": channel, "email": channel, "push": channel } );
                        structDelete( variables.config, "digests" );
                    }
                }
            } );
            it( "admits 101 requests without any mapped Plan or result models and freezes replay choices", () => {
                guardModels();
                var inputs = [];
                for ( var index = 1; index <= 101; index++ ) {
                    inputs.append( notificationRequest( createUUID() ) );
                }
                variables.service.admitRequests( requests = inputs, connection = "reference", queue = "bulk" );
                expect( variables.adapter.getReferences().len() ).toBe( 202 );
                expect( variables.adapter.getReferenceOptions() ).toBe( [ { "connection": "reference", "queue": "bulk" } ] );
                var first = variables.deliveries.find( variables.adapter.getReferences()[ 1 ].id );
                expect( variables.deliveries.forEvent( first.eventId ).len() ).toBe( 3 );
                expect(
                    variables.deliveries
                        .forEvent( first.eventId )
                        .filter( ( row ) => row.state == "suppressed" )
                        .len()
                ).toBe( 1 );
                inputs[ 1 ].notifiables = [
                    variables.owner,
                    new tests.resources.InboxRecipient().setId( createUUID() )
                ];
                variables.service.admitRequests( [ inputs[ 1 ] ] );
                expect( variables.adapter.getReferences().len() ).toBe( 202 );
                expect( variables.deliveries.forEvent( first.eventId ).len() ).toBe( 3 );
            } );
            it( "keeps per-event custom queue groups, defaults, suppression and replay isolated", () => {
                var inputs = [];
                for ( var index = 1; index <= 5; index++ ) {
                    inputs.append( notificationRequest( createUUID() ) );
                }
                for ( var index in [ 1, 2 ] ) {
                    inputs[ index ].connection = "one";
                    inputs[ index ].queue = "Priority";
                }
                inputs[ 3 ].connection = "two";
                inputs[ 3 ].queue = "priority";
                inputs[ 5 ].connection = "ignored";
                inputs[ 5 ].queue = "suppressed";
                inputs[ 5 ].properties.choices = { "database": false, "email": false, "push": false };
                variables.service.admitRequests( inputs );
                var batches = variables.adapter.getReferenceBatches();
                expect( batches.len() ).toBe( 3 );
                expect( variables.adapter.getReferences().len() ).toBe( 8 );
                var total = 0;
                for ( var batch in batches ) {
                    expect( batch.argumentNames ).notToInclude( "groupkey" );
                    expect( batch.references.every( ( reference ) => reference.state == "queued" ) ).toBeTrue();
                    if ( structIsEmpty( batch.options ) ) {
                        expect( batch.references.len() ).toBe( 2 );
                        expect( batch.argumentNames ).toBe( [ "connection", "queue", "references" ] );
                    } else if ( compare( batch.options.queue, "Priority" ) == 0 ) {
                        expect( batch.options.connection ).toBe( "one" );
                        expect( batch.references.len() ).toBe( 4 );
                        expect( batch.argumentNames ).toBe( [ "connection", "queue", "references" ] );
                    } else {
                        expect( compare( batch.options.queue, "priority" ) ).toBe( 0 );
                        expect( batch.options.connection ).toBe( "two" );
                        expect( batch.references.len() ).toBe( 2 );
                    }
                    total += batch.references.len();
                }
                expect( total ).toBe( 8 );
                variables.service.admitRequests( inputs );
                expect( variables.adapter.getReferenceBatches().len() ).toBe( 3 );
                expect( variables.adapter.getReferences().len() ).toBe( 8 );
            } );
            it( "retains per-request transient snapshotter resolution in both batch APIs", () => {
                var counter = { "instances": [] };
                variables.injector
                    .getScope( "singleton" )
                    .getSingletons()
                    .remove( "notificationsnapshothasher@megaphone" );
                variables.injector
                    .getBinder()
                    .map( "NotificationSnapshotHasher@megaphone" )
                    .to( "tests.resources.TransientSnapshotHasher" )
                    .initArg( name = "counter", value = counter )
                    .into( "NOSCOPE" );
                try {
                    variables.service.admitRequests( [ notificationRequest( createUUID() ), notificationRequest( createUUID() ) ] );
                    expect( counter.instances.len() ).toBe( 8 );
                    expect( counter.instances[ 1 ] ).toBe( counter.instances[ 4 ] );
                    expect( counter.instances[ 5 ] ).toBe( counter.instances[ 8 ] );
                    expect( counter.instances[ 1 ] ).notToBe( counter.instances[ 5 ] );
                    counter.instances.clear();
                    var plans = variables.service.planMany( [ notificationRequest( createUUID() ), notificationRequest( createUUID() ) ] );
                    expect( plans.len() ).toBe( 2 );
                    expect( counter.instances.len() ).toBe( 8 );
                    expect( counter.instances[ 1 ] ).notToBe( counter.instances[ 5 ] );
                } finally {
                    variables.injector
                        .getBinder()
                        .map( "NotificationSnapshotHasher@megaphone" )
                        .to( "megaphone.models.Delivery.NotificationSnapshotHasher" )
                        .asSingleton();
                }
            } );
            it( "retains transaction rollback on late identity conflict and adapter failure", () => {
                var existing = notificationRequest( createUUID() );
                variables.service.admitRequests( [ existing ] );
                var fresh = notificationRequest( createUUID() );
                existing.properties.message = "conflict";
                expect( () => variables.service.admitRequests( [ fresh, existing ] ) ).toThrow( "Megaphone.Events.IdentityConflict" );
                expect( eventCount( [ fresh.options.eventKey, existing.options.eventKey ] ) ).toBe( 0 );
                var failing = new tests.resources.BulkReferenceQueueFixture( true );
                variables.config.queue.queueAdapter = failing;
                var another = notificationRequest( createUUID() );
                expect( () => variables.service.admitRequests( [ another ] ) ).toThrow( "QueueFixtureUnavailable" );
                expect( eventCount( [ another.options.eventKey ] ) ).toBe( 0 );
                expect( isNull( variables.deliveries.find( failing.getReferences()[ 1 ].id ) ) ).toBeTrue();
            } );
            it( "keeps cutoffs, explicit admission override, and caller rollback", () => {
                var input = notificationRequest( createUUID() );
                input.options.admitAfter = dateAdd( "d", 1, input.options.occurredAt );
                variables.service.admitRequests( [ input ] );
                expect( variables.adapter.getReferences() ).toBeEmpty();
                variables.service.admitRequests( requests = [ input ], alreadyAdmitted = true );
                // plan() captures expired audiences as empty, even for an explicit admission override.
                expect( variables.adapter.getReferences() ).toBeEmpty();
                expect( eventCount( [ input.options.eventKey ] ) ).toBe( 1 );
                transactionRollback();
                expect( eventCount( [ input.options.eventKey ] ) ).toBe( 0 );
            } );
            it( "uses transformed mapped Plans and typed deliveries for a legacy adapter", () => {
                var legacy = new tests.resources.DurableQueueFixture();
                variables.config.queue.queueAdapter = legacy;
                variables.injector
                    .getBinder()
                    .map( "NotificationPlan@megaphone" )
                    .to( "tests.resources.TransformingNotificationPlan" );
                var input = notificationRequest( createUUID() );
                variables.service.admitRequests( [ input ] );
                variables.service.admitRequests( [ input ] );
                expect( legacy.getDeliveries().len() ).toBe( 2 );
                var event = variables.events.find( legacy.getDeliveries()[ 1 ].eventId );
                expect( event.payload.mappingMarker ).toBe( "custom-plan" );
                var runtime = variables.injector.getInstance( "NotificationRuntime@megaphone" );
                expect( event.payloadHash ).toBe(
                    runtime.digest( event.payload, { "namespace": event.namespace, "kind": "payload" } )
                );
                var work = variables.deliveries.find( legacy.getDeliveries()[ 1 ].id );
                expect( work.routingData.mappingMarker ).toBe( "custom-plan" );
                expect( work.routingHash ).toBe(
                    runtime.digest( work.routingData, { "namespace": event.namespace, "kind": "routing" } )
                );
            } );
            it( "constructs mapped Plans before any writes for collection fallback", () => {
                variables.service.setChannels( {
                    "database": new tests.resources.CollectionChannelFixture(),
                    "email": new tests.resources.CollectionChannelFixture(),
                    "push": new tests.resources.CollectionChannelFixture()
                } );
                variables.injector
                    .getBinder()
                    .map( "NotificationPlan@megaphone" )
                    .to( "tests.resources.ResultModelConstructionGuard" );
                var input = notificationRequest( createUUID() );
                expect( () => variables.service.admitRequests( [ input ] ) ).toThrow(
                    type = "Builder.BuildCFCDependencyException",
                    regex = "No-result admission constructed a public result model"
                );
                expect( eventCount( [ input.options.eventKey ] ) ).toBe( 0 );
                expect( variables.adapter.getReferences() ).toBeEmpty();
            } );
            it( "constructs mapped Plans before any writes for global digest fallback", () => {
                variables.config.digests = { "independent": {} };
                variables.injector
                    .getBinder()
                    .map( "NotificationPlan@megaphone" )
                    .to( "tests.resources.ResultModelConstructionGuard" );
                var input = notificationRequest( createUUID() );
                expect( () => variables.service.admitRequests( [ input ] ) ).toThrow(
                    type = "Builder.BuildCFCDependencyException",
                    regex = "No-result admission constructed a public result model"
                );
                expect( eventCount( [ input.options.eventKey ] ) ).toBe( 0 );
                expect( variables.adapter.getReferences() ).toBeEmpty();
            } );
        } );
    }
    private numeric function eventCount( required array keys ) {
        return variables.injector
            .getInstance( "QueryBuilder@qb" )
            .from( "megaphone_events" )
            .whereIn( "eventKey", arguments.keys )
            .count();
    }
    private void function guardModels() {
        for (
            var name in [
                "NotificationPlan",
                "NotificationEvent",
                "NotificationDelivery",
                "NotificationPublication"
            ]
        ) {
            variables.injector
                .getBinder()
                .map( name & "@megaphone" )
                .to( "tests.resources.ResultModelConstructionGuard" );
        }
    }
    private void function restoreModels() {
        for (
            var name in [
                "NotificationPlan",
                "NotificationEvent",
                "NotificationDelivery",
                "NotificationPublication"
            ]
        ) {
            variables.injector
                .getBinder()
                .map( name & "@megaphone" )
                .to( "megaphone.models.Delivery." & name );
        }
    }

}
