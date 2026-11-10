component extends="tests.specs.integration.DeliveryStoreSpec" {

    function run() {
        describe( "Public event delivery state groups", () => {
            aroundEach( ( spec ) => {
                transaction {
                    try {
                        spec.body();
                    } finally {
                        transactionRollback();
                    }
                }
            } );
            it( "retains event identity and state totals after application constraints", () => {
                var first = event();
                var second = event();
                var foreign = event();
                var work = variables.deliveries.enqueue(
                    first.id,
                    "User",
                    "wanted",
                    "email",
                    {},
                    "fixture"
                );
                var lease = variables.deliveries.claim( work.id );
                variables.deliveries.startTransport( work.id, lease.token );
                variables.deliveries.complete( work.id, lease.token, "accepted" );
                variables.deliveries.enqueue(
                    first.id,
                    "User",
                    "other",
                    "email",
                    {},
                    "fixture"
                );
                variables.deliveries.enqueue(
                    second.id,
                    "User",
                    "wanted",
                    "email",
                    {},
                    "fixture"
                );
                variables.deliveries.enqueue(
                    second.id,
                    "User",
                    "other",
                    "email",
                    {},
                    "fixture"
                );
                variables.deliveries.enqueue(
                    second.id,
                    "User",
                    "wanted",
                    "database",
                    {},
                    "fixture"
                );
                variables.deliveries.enqueue(
                    foreign.id,
                    "User",
                    "wanted",
                    "email",
                    {},
                    "fixture"
                );
                var identities = [ first.id, second.id ];
                var filter = ( query ) => query
                    .whereIn( "delivery.eventId", identities )
                    .where( "delivery.channel", "email" );
                var counts = variables.operations.getEventStateCounts( filter );
                expect( counts.len() ).toBe( 3 );
                var one = counts.filter( ( row ) => row.eventId == first.id );
                var two = counts.filter( ( row ) => row.eventId == second.id );
                expect( one.len() ).toBe( 2 );
                expect( one.map( ( row ) => row.state ) ).toBe( [ "accepted", "queued" ] );
                expect( one.every( ( row ) => row.channelName == "email" && row.total == 1 ) ).toBeTrue();
                expect( two.len() ).toBe( 1 );
                expect( two[ 1 ].state ).toBe( "queued" );
                expect( two[ 1 ].total ).toBe( 2 );
                var legacy = variables.operations.getStateCounts( filter );
                expect( legacy.len() ).toBe( 2 );
                expect( legacy[ 1 ].state ).toBe( "accepted" );
                expect( legacy[ 1 ].total ).toBe( 1 );
                expect( legacy[ 2 ].state ).toBe( "queued" );
                expect( legacy[ 2 ].total ).toBe( 3 );
            } );
            it( "keeps channels separate and does not retain constraints between calls", () => {
                var selected = event();
                variables.deliveries.enqueue(
                    selected.id,
                    "User",
                    "wanted",
                    "email",
                    {},
                    "fixture"
                );
                variables.deliveries.enqueue(
                    selected.id,
                    "User",
                    "wanted",
                    "database",
                    {},
                    "fixture"
                );
                var counts = variables.operations.getEventStateCounts( ( query ) => query.where( "delivery.eventId", selected.id ).where( "delivery.channel", "email" ) );
                expect( counts.len() ).toBe( 1 );
                expect( counts[ 1 ].channelName ).toBe( "email" );
                counts = variables.operations.getEventStateCounts();
                expect( counts.len() ).toBe( 2 );
                expect( counts.map( ( row ) => row.channelName ) ).toBe( [ "database", "email" ] );
                expect(
                    counts.every( ( row ) => row.eventId == selected.id && row.state == "queued" && row.total == 1 )
                ).toBeTrue();
            } );
            it( "counts distinct deliveries when an application join multiplies rows", () => {
                var selected = event();
                variables.deliveries.enqueue(
                    selected.id,
                    "User",
                    "wanted",
                    "email",
                    {},
                    "fixture"
                );
                variables.deliveries.enqueue(
                    selected.id,
                    "User",
                    "other",
                    "email",
                    {},
                    "fixture"
                );
                var filter = ( query ) => query
                    .join( variables.deliveries.getTableName() & " AS related", "related.eventId", "delivery.eventId" )
                    .where( "delivery.eventId", selected.id );
                var counts = variables.operations.getEventStateCounts( filter );
                expect( counts.len() ).toBe( 1 );
                expect( counts[ 1 ].eventId ).toBe( selected.id );
                expect( counts[ 1 ].total ).toBe( 2 );
                var legacy = variables.operations.getStateCounts( filter );
                expect( legacy.len() ).toBe( 1 );
                expect( legacy[ 1 ].total ).toBe( 2 );
                var recipientCounts = variables.operations.getEventStateCounts( ( query ) => {
                    filter( query );
                    query.where( "delivery.recipientId", "wanted" );
                } );
                expect( recipientCounts.len() ).toBe( 1 );
                expect( recipientCounts[ 1 ].total ).toBe( 1 );
            } );
            it( "returns no state groups for an empty selection", () => {
                expect( variables.operations.getEventStateCounts( ( query ) => query.whereRaw( "1=0" ) ) ).toBeEmpty();
            } );
        } );
    }

    private struct function event() {
        return variables.events.record(
            namespace = "state-count-fixture",
            eventKey = createUUID(),
            version = 1,
            type = "published",
            payload = {},
            payloadHash = "fixture"
        );
    }

}
