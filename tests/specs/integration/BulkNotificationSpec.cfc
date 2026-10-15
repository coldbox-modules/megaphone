/** Real public planning, durable admission, and preference resolution across chunk boundaries. */
component extends="tests.resources.BulkNotificationSpecBase" {

    function run() {
        describe( "Atomic bulk notification admission", () => {
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
            it( "captures 101 ordered plans with empty queue options and exact scalar snapshot hashes", () => {
                var requests = [];
                for ( var index = 1; index <= 101; index++ ) {
                    requests.append( notificationRequest( createUUID(), "message-" & index ) );
                }
                var plans = variables.service.planMany( requests );
                expect( plans.len() ).toBe( 101 );
                for ( var index = 1; index <= plans.len(); index++ ) {
                    var scalar = variables.service.plan( argumentCollection = requests[ index ] ).getMemento();
                    var bulk = plans[ index ].getMemento();
                    expect( bulk.event ).toBe( scalar.event );
                    expect( plans[ index ].getQueueOptions() ).toBeEmpty();
                    expect( bulk.deliveries.map( ( item ) => item.routingHash ) ).toBe(
                        scalar.deliveries.map( ( item ) => item.routingHash )
                    );
                }
                expect( variables.adapter.getDeliveries() ).toBeEmpty();
                var publications = variables.service.queuePlans(
                    plans = plans,
                    connection = "bulk-connection",
                    queue = "bulk-queue"
                );
                expect( publications.len() ).toBe( 101 );
                expect( variables.adapter.getBatches().len() ).toBe( 1 );
                expect( variables.adapter.getBatches()[ 1 ].connection ).toBe( "bulk-connection" );
                expect( variables.adapter.getBatches()[ 1 ].queue ).toBe( "bulk-queue" );
                expect( variables.adapter.getDeliveries().len() ).toBe( 202 );
                for ( var publication in publications ) {
                    expect( publication.getEvent().getCreated() ).toBeTrue();
                    expect( publication.getDeliveries().map( ( item ) => item.getState() ) ).toBe( [ "queued", "queued", "suppressed" ] );
                }
            } );
            it( "freezes one audience for repeated new and replay event plans beyond 100 inputs", () => {
                var inputRequest = notificationRequest( createUUID() );
                var requests = [];
                for ( var index = 1; index <= 101; index++ ) {
                    requests.append( inputRequest );
                }
                var publications = variables.service.queuePlans( variables.service.planMany( requests ) );
                var ids = publications[ 1 ].getDeliveries().map( ( item ) => item.getId() );
                expect( variables.adapter.getDeliveries().len() ).toBe( 2 );
                for ( var publication in publications ) {
                    expect(
                        publication
                            .getDeliveries()
                            .map( ( item ) => item.getId() )
                            .sort( "text" )
                    ).toBe( ids.sort( "text" ) );
                }
                inputRequest.notifiables = [
                    variables.owner,
                    new tests.resources.InboxRecipient().setId( createUUID() )
                ];
                var replayed = variables.service.queuePlans( variables.service.planMany( requests ) );
                for ( var publication in replayed ) {
                    expect( publication.getEvent().getCreated() ).toBeFalse();
                    expect( publication.getDeliveries().len() ).toBe( 3 );
                    expect(
                        publication
                            .getDeliveries()
                            .filter( ( item ) => item.getState() == "suppressed" )
                            .len()
                    ).toBe( 1 );
                }
                expect( variables.adapter.getDeliveries().len() ).toBe( 2 );
            } );
            it( "falls back to scalar queue adapters without requeueing a replay", () => {
                var legacy = new tests.resources.DurableQueueFixture();
                variables.config.queue.queueAdapter = legacy;
                var plans = variables.service.planMany( [ notificationRequest( createUUID() ), notificationRequest( createUUID() ) ] );
                variables.service.queuePlans( plans );
                expect( legacy.getDeliveries().len() ).toBe( 4 );
                variables.service.queuePlans( plans );
                expect( legacy.getDeliveries().len() ).toBe( 4 );
            } );
            it( "uses the optional ordered bulk hasher without changing custom scalar hashes", () => {
                var hasher = new tests.resources.BulkSnapshotHasherFixture();
                variables.config.queue.snapshotHasher = hasher;
                var input = notificationRequest( createUUID() );
                var plans = variables.service.planMany( [ input, notificationRequest( createUUID(), "different" ) ] );
                expect( hasher.getCalls() ).toBe( 1 );
                expect( plans[ 1 ].getEvent().payloadHash ).toBe(
                    variables.service.plan( argumentCollection = input ).getEvent().payloadHash
                );
                expect( left( plans[ 2 ].getDeliveries()[ 1 ].routingHash, 7 ) ).toBe( "custom-" );
            } );
            it( "uses one configured compiler per chunk while preserving typed identity matches and duplicate ordinals", () => {
                var key = "Mixed-case-'?-" & createUUID();
                var event = variables.events.record(
                    namespace = "bulk-compiler",
                    eventKey = key,
                    version = 1,
                    type = "notice",
                    payload = {},
                    payloadHash = "frozen"
                );
                var identities = [];
                for ( var index = 1; index <= 101; index++ ) {
                    identities.append( { "namespace": "bulk-compiler", "eventKey": key, "version": { "value": 1, "cfsqltype": "integer" } } );
                }
                identities[ 51 ].eventKey = uCase( key );
                var compilers = [];
                var table = "megaphone_events AS configured_identity_source";
                var rows = new megaphone.models.Storage.BulkRecords().read(
                    queryFactory = () => {
                        var compiler = variables.injector
                            .getInstance( "QueryBuilder@qb" )
                            .from( table )
                            .mergeDefaultOptions( { "timeout": 15 } );
                        compilers.append( compiler );
                        return compiler;
                    },
                    identities = identities,
                    tableName = table
                );
                expect( compilers.len() ).toBe( 2 );
                expect( rows.len() ).toBe( 101 );
                for ( var index = 1; index <= rows.len(); index++ ) {
                    if ( index == 51 && variables.isPostgres ) {
                        expect( rows[ index ] ).toBeEmpty();
                    } else {
                        expect( rows[ index ].len() ).toBe( 1 );
                        expect( rows[ index ][ 1 ].id ).toBe( event.id );
                    }
                }
                for ( var compiler in compilers ) {
                    expect( compiler.getDefaultOptions().timeout ).toBe( 15 );
                    expect( compiler.getQueryLog().len() ).toBe( 1 );
                    expect( compiler.getQueryLog()[ 1 ].sql ).notToInclude( key );
                }
            } );
            it( "rolls back every event and delivery if bulk queue insertion fails", () => {
                var failing = new tests.resources.BulkQueueFixture( true );
                variables.config.queue.queueAdapter = failing;
                var plans = variables.service.planMany( [ notificationRequest( createUUID() ), notificationRequest( createUUID() ) ] );
                expect( () => variables.service.queuePlans( plans ) ).toThrow( "QueueFixtureUnavailable" );
                var captured = failing.getDeliveries()[ 1 ];
                expect( isNull( variables.events.find( captured.eventId ) ) ).toBeTrue();
                expect( isNull( variables.deliveries.find( captured.id ) ) ).toBeTrue();
            } );
            it( "rolls back earlier insert chunks on a late event identity conflict", () => {
                var key = createUUID();
                variables.events.record(
                    namespace = "bulk-test",
                    eventKey = key,
                    version = 1,
                    type = "notice",
                    payload = {},
                    payloadHash = "original"
                );
                var inputs = [];
                var firstKey = createUUID();
                for ( var index = 1; index <= 101; index++ ) {
                    inputs.append( {
                        "namespace": "bulk-test",
                        "eventKey": index == 1 ? firstKey : createUUID(),
                        "version": 1,
                        "type": "notice",
                        "payload": {},
                        "payloadHash": "new"
                    } );
                }
                inputs[ 101 ].eventKey = key;
                expect( () => variables.events.recordMany( inputs ) ).toThrow( "Megaphone.Events.IdentityConflict" );
                expect(
                    variables.injector
                        .getInstance( "QueryBuilder@qb" )
                        .from( "megaphone_events" )
                        .where( "eventKey", firstKey )
                        .count()
                ).toBe( 0 );
            } );
            it( "resolves 101 preference requests in order with exact scalar precedence and ownership", () => {
                var requests = [];
                for ( var index = 1; index <= 101; index++ ) {
                    var recipient = new tests.resources.InboxRecipient().setId( createUUID() );
                    variables.preferenceService.setPreference(
                        recipient,
                        "notice",
                        "account",
                        "email",
                        "on"
                    );
                    variables.preferenceService.setPreference(
                        recipient,
                        "notice",
                        "production:" & index,
                        "email",
                        "off"
                    );
                    requests.append( {
                        "notifiable": recipient,
                        "notificationType": "notice",
                        "defaults": { "email": false, "database": true },
                        "scopeKeys": [ "account", "production:" & index ]
                    } );
                }
                requests.append( {
                    "notifiable": variables.owner,
                    "notificationType": "notice",
                    "defaults": { "email": true },
                    "scopeKeys": []
                } );
                var results = variables.preferenceService.resolvePreferencesMany( requests );
                expect( results.len() ).toBe( 102 );
                for ( var index = 1; index <= requests.len(); index++ ) {
                    expect( results[ index ] ).toBe(
                        variables.preferenceService.resolvePreferences( argumentCollection = requests[ index ] )
                    );
                }
                expect( results[ 1 ].effective.email.source ).toBe( "production:1" );
                expect( results[ 102 ].effective.email.enabled ).toBeTrue();
                expect( results[ 102 ].scopes ).toBeEmpty();
            } );
        } );
    }

}
