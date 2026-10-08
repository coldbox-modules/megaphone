component extends="tests.specs.integration.DeliveryStoreSpec" {

    function beforeAll() {
        super.beforeAll();
        variables.injector
            .getBinder()
            .map( "DurableNotificationService@megaphone" )
            .to( "megaphone.models.DurableNotificationService" );
        variables.publisher = variables.injector.getInstance( "DurableNotificationService@megaphone" );
    }
    function run() {
        describe( "Transactional durable publication", () => {
            aroundEach( ( spec ) => {
                transaction {
                    try {
                        variables.identity = {
                            "namespace": "test",
                            "eventKey": createUUID(),
                            "version": 1,
                            "type": "submitted",
                            "payload": { "subjectId": "audition" },
                            "payloadHash": "snapshot"
                        };
                        spec.body();
                    } finally {
                        transactionRollback();
                    }
                }
            } );
            it( "rejects retired occurrence times without queueing or changing existing pending work", () => {
                var cutoff = dateAdd( "d", -365, now() );
                variables.identity.createdDate = dateAdd( "d", -1, cutoff );
                var adapter = new tests.resources.DurableQueueFixture();
                var existing = variables.publisher.publish(
                    event = variables.identity,
                    intents = [ intent( "database", true ) ]
                );
                var expired = variables.publisher.publish(
                    event = variables.identity,
                    intents = [ intent( "email", true ) ],
                    queueAdapter = adapter,
                    admitAfter = cutoff
                );
                expect( expired.event.expired ).toBeTrue();
                expect( expired.deliveries ).toBeEmpty();
                expect( adapter.getDeliveries() ).toBeEmpty();
                expect( variables.deliveries.forEvent( existing.event.id ).len() ).toBe( 1 );
                expect( variables.publisher.canPublish( cutoff, cutoff ) ).toBeTrue();
                expect( variables.publisher.canPublish( variables.identity.createdDate, cutoff ) ).toBeFalse();
            } );
            it( "requires a persisted occurrence time when admission is bounded", () => {
                expect( function() {
                    return variables.publisher.publish( event = variables.identity, intents = [], admitAfter = now() );
                } ).toThrow( type = "Megaphone.Events.OccurrenceRequired" );
            } );
            it( "persists independent channel choices and queues only fresh enabled work", () => {
                var adapter = new tests.resources.DurableQueueFixture();
                var published = variables.publisher.publish(
                    event = variables.identity,
                    intents = [ intent( "email", false ), intent( "database", true ) ],
                    queueAdapter = adapter
                );
                expect( published.event.created ).toBeTrue();
                expect( published.deliveries.len() ).toBe( 2 );
                expect( published.deliveries[ 1 ].state ).toBe( "suppressed" );
                expect( published.deliveries[ 2 ].state ).toBe( "queued" );
                expect( adapter.getDeliveries().len() ).toBe( 1 );
                expect( adapter.getDeliveries()[ 1 ].channel ).toBe( "database" );
            } );
            it( "does not replay channels or add newly eligible recipients on event retry", () => {
                var adapter = new tests.resources.DurableQueueFixture();
                var first = variables.publisher.publish(
                    event = variables.identity,
                    intents = [ intent( "email", false ) ],
                    queueAdapter = adapter
                );
                var later = intent( "push", true );
                later.recipientId = "newly-authorized-user";
                var repeated = variables.publisher.publish(
                    event = variables.identity,
                    intents = [ intent( "email", true ), later ],
                    queueAdapter = adapter
                );
                expect( repeated.event.created ).toBeFalse();
                expect( repeated.event.id ).toBe( first.event.id );
                expect( repeated.deliveries.len() ).toBe( 1 );
                expect( repeated.deliveries[ 1 ].state ).toBe( "suppressed" );
                expect( adapter.getDeliveries().len() ).toBe( 0 );
            } );
            it( "rolls back event and work when transactional queue insertion fails", () => {
                var adapter = new tests.resources.DurableQueueFixture( true );
                expect( function() {
                    return variables.publisher.publish(
                        event = variables.identity,
                        intents = [ intent( "email", true ) ],
                        queueAdapter = adapter
                    );
                } ).toThrow( type = "QueueFixtureUnavailable" );
                var attempted = adapter.getDeliveries()[ 1 ];
                expect( isNull( variables.events.find( attempted.eventId ) ) ).toBeTrue();
                expect( isNull( variables.deliveries.find( attempted.id ) ) ).toBeTrue();
            } );
            it( "stores durable work without requiring a queue implementation", () => {
                var published = variables.publisher.publish(
                    event = variables.identity,
                    intents = [ intent( "email", true ) ]
                );
                expect( variables.deliveries.find( published.deliveries[ 1 ].id ).state ).toBe( "queued" );
                expect( variables.deliveries.due().len() ).toBe( 1 );
            } );
        } );
    }
    private struct function intent( required string channel, required boolean enabled ) {
        return {
            "recipientType": "User",
            "recipientId": "recipient",
            "channel": arguments.channel,
            "enabled": arguments.enabled,
            "routingData": { "organizationId": "org" },
            "routingHash": "routing"
        };
    }

}
