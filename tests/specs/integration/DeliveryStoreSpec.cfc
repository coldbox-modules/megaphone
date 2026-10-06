component extends="tests.specs.integration.EventStoreSpec" {

    function beforeAll() {
        super.beforeAll();
        variables.injector
            .getBinder()
            .map( "DeliveryStore@megaphone" )
            .to( "megaphone.models.DeliveryStore" );
        variables.deliveries = variables.injector.getInstance( "DeliveryStore@megaphone" );
    }

    function run() {
        describe( "Durable channel and device delivery", () => {
            aroundEach( ( spec ) => {
                transaction {
                    try {
                        variables.event = variables.events.record(
                            namespace = "test",
                            eventKey = createUUID(),
                            version = 1,
                            type = "submitted",
                            payload = { "message": "Submitted" },
                            payloadHash = "snapshot"
                        );
                        variables.clock = now();
                        spec.body();
                    } finally {
                        transactionRollback();
                    }
                }
            } );
            it( "audits one bounded recovery without resetting attempts or resending accepted work", () => {
                var work = enqueue();
                for ( var number = 1; number <= 5; number++ ) {
                    var lease = variables.deliveries.claim( work.id );
                    expect( lease.status ).toBe( "ready" );
                    variables.deliveries.startTransport( work.id, lease.token );
                    variables.deliveries.complete(
                        id = work.id,
                        token = lease.token,
                        outcome = "retryable",
                        providerReference = "rejection-" & number,
                        retryDate = dateAdd( "s", -1, now() )
                    );
                }
                expect( variables.deliveries.claim( work.id ).status ).toBe( "exhausted" );
                var prior = variables.deliveries.find( work.id );
                var adapter = new tests.resources.DurableQueueFixture();
                var key = createUUID();
                var version = variables.deliveries.recoveryVersion( prior );
                var result = variables.deliveries.requestRecovery(
                    work.id,
                    key,
                    "operator",
                    version,
                    ( row ) => {
                        return { status: "ready" };
                    },
                    adapter
                );
                expect( result.status ).toBe( "saved" );
                expect( result.replayed ).toBeFalse();
                expect( result.delivery.attemptCount ).toBe( 5 );
                expect( result.delivery.transportCount ).toBe( 5 );
                expect( result.delivery.recoveryAllowance ).toBe( 1 );
                expect( adapter.getDeliveries().len() ).toBe( 1 );
                var history = variables.deliveries.recoveryHistory( work.id );
                expect( history.results.len() ).toBe( 1 );
                expect( history.results[ 1 ].priorTransportCount ).toBe( 5 );
                expect( history.results[ 1 ].priorProviderReference ).toBe( "rejection-5" );
                var next = variables.deliveries.claim( work.id );
                expect( next.status ).toBe( "ready" );
                expect( next.delivery.attemptCount ).toBe( 6 );
                variables.deliveries.startTransport( work.id, next.token );
                variables.deliveries.complete(
                    id = work.id,
                    token = next.token,
                    outcome = "accepted",
                    providerReference = "accepted-sixth"
                );
                expect(
                    variables.deliveries.requestRecovery(
                        work.id,
                        key,
                        "operator",
                        version,
                        ( row ) => {
                            return { status: "ready" };
                        },
                        adapter
                    ).replayed
                ).toBeTrue();
                expect( adapter.getDeliveries().len() ).toBe( 1 );
                var accepted = variables.deliveries.find( work.id );
                expect(
                    variables.deliveries.requestRecovery(
                        work.id,
                        createUUID(),
                        "operator",
                        variables.deliveries.recoveryVersion( accepted ),
                        ( row ) => {
                            return { status: "ready" };
                        },
                        adapter
                    ).status
                ).toBe( "conflict" );
                expect( variables.deliveries.attempts( work.id ).len() ).toBe( 6 );
                expect( variables.deliveries.find( work.id ).providerReference ).toBe( "accepted-sixth" );
            } );
            it( "never revives suppression ambiguity or an active lease", () => {
                var adapter = new tests.resources.DurableQueueFixture();
                var suppressed = enqueue( initialState = "suppressed" );
                var busy = enqueue( device = "busy" );
                variables.deliveries.claim( busy.id );
                var ambiguous = variables.deliveries.importDelivery(
                    {
                        eventId: variables.event.id,
                        recipientType: "User",
                        recipientId: "unknown",
                        channel: "email",
                        routingData: {},
                        routingHash: "unknown"
                    },
                    { state: "ambiguous", attemptCount: 1, createdDate: now() }
                );
                for (
                    var work in [
                        variables.deliveries.find( suppressed.id ),
                        variables.deliveries.find( busy.id ),
                        ambiguous
                    ]
                ) {
                    expect(
                        variables.deliveries.requestRecovery(
                            work.id,
                            createUUID(),
                            "operator",
                            variables.deliveries.recoveryVersion( work ),
                            ( row ) => {
                                return { status: "ready" };
                            },
                            adapter
                        ).status
                    ).toBe( "conflict" );
                    expect( variables.deliveries.recoveryHistory( work.id ).results.len() ).toBe( 0 );
                }
                expect( adapter.getDeliveries().len() ).toBe( 0 );
            } );
            it( "rejects stale and ineligible commands and preserves scheduled backoff", () => {
                var work = enqueue();
                var lease = variables.deliveries.claim( work.id );
                var later = dateAdd( "h", 2, now() );
                variables.deliveries.complete(
                    id = work.id,
                    token = lease.token,
                    outcome = "retryable",
                    reason = "eligibility-error",
                    retryDate = later
                );
                work = variables.deliveries.find( work.id );
                var version = variables.deliveries.recoveryVersion( work );
                var adapter = new tests.resources.DurableQueueFixture();
                expect(
                    variables.deliveries.requestRecovery(
                        work.id,
                        createUUID(),
                        "operator",
                        repeatString( "a", 64 ),
                        ( row ) => {
                            return { status: "ready" };
                        },
                        adapter
                    ).status
                ).toBe( "conflict" );
                expect(
                    variables.deliveries.requestRecovery(
                        work.id,
                        createUUID(),
                        "operator",
                        version,
                        ( row ) => {
                            return { status: "suppressed" };
                        },
                        adapter
                    ).status
                ).toBe( "ineligible" );
                expect( variables.deliveries.recoveryHistory( work.id ).results.len() ).toBe( 0 );
                var key = createUUID();
                var recovered = variables.deliveries.requestRecovery(
                    work.id,
                    key,
                    "operator",
                    version,
                    ( row ) => {
                        return { status: "ready" };
                    },
                    adapter
                );
                expect( recovered.status ).toBe( "saved" );
                expect( dateCompare( recovered.delivery.availableDate, later, "s" ) ).toBe( 0 );
                expect( variables.deliveries.due().len() ).toBe( 0 );
                expect(
                    variables.deliveries.requestRecovery(
                        work.id,
                        key,
                        "different-operator",
                        version,
                        ( row ) => {
                            return { status: "ready" };
                        },
                        adapter
                    ).status
                ).toBe( "conflict" );
                expect( adapter.getDeliveries().len() ).toBe( 1 );
            } );
            it( "does not grant more transport allowance after the lifetime recovery cap", () => {
                var work = variables.deliveries.importDelivery(
                    {
                        eventId: variables.event.id,
                        recipientType: "User",
                        recipientId: "capped",
                        channel: "email",
                        routingData: {},
                        routingHash: "capped"
                    },
                    { state: "permanent", attemptCount: 50, createdDate: now() }
                );
                variables.injector
                    .getInstance( "QueryBuilder@qb" )
                    .from( "megaphone_deliveries" )
                    .where( "id", work.id )
                    .update( { "recoveryAllowance": 45 } );
                work = variables.deliveries.find( work.id );
                var adapter = new tests.resources.DurableQueueFixture();
                expect( variables.deliveries.canRecover( work ) ).toBeFalse();
                expect(
                    variables.deliveries.requestRecovery(
                        work.id,
                        createUUID(),
                        "operator",
                        variables.deliveries.recoveryVersion( work ),
                        ( row ) => {
                            return { status: "ready" };
                        },
                        adapter
                    ).status
                ).toBe( "conflict" );
                expect( variables.deliveries.recoveryHistory( work.id ).results.len() ).toBe( 0 );
                expect( adapter.getDeliveries().len() ).toBe( 0 );
            } );
            it( "deduplicates event recipient channel device work without reviving suppression", () => {
                var first = enqueue( initialState = "suppressed" );
                expect( enqueue().id ).toBe( first.id );
                expect( variables.deliveries.find( first.id ).state ).toBe( "suppressed" );
                expect( enqueue( device = "second" ).id ).notToBe( first.id );
                expect( enqueue( channel = "email" ).id ).notToBe( first.id );
                expect( enqueue( recipient = "different" ).id ).notToBe( first.id );
                expect( () => enqueue( routingHash = "changed" ) ).toThrow(
                    type = "Megaphone.Delivery.IdentityConflict"
                );
            } );
            it( "filters operator pages before limiting and returns decoded routing with stable pages", () => {
                var first = enqueue( recipient = "wanted" );
                var second = enqueue( recipient = "wanted", channel = "database", initialState = "suppressed" );
                enqueue( recipient = "foreign" );
                var filter = ( query ) => query.where( "delivery.recipientId", "wanted" );
                var one = variables.deliveries.getPage( 1, 0, filter );
                var two = variables.deliveries.getPage( 1, 1, filter );
                expect( one.results.len() ).toBe( 1 );
                expect( one.hasMore ).toBeTrue();
                expect( two.results.len() ).toBe( 1 );
                expect( two.hasMore ).toBeFalse();
                expect( one.results[ 1 ].id ).notToBe( two.results[ 1 ].id );
                expect( one.results[ 1 ].recipientId ).toBe( "wanted" );
                expect( isStruct( one.results[ 1 ].routingData ) ).toBeTrue();
                var suppressed = variables.deliveries.getPage(
                    50,
                    0,
                    ( query ) => {
                        filter( query );
                        query.where( "delivery.state", "suppressed" );
                    }
                );
                expect( suppressed.results.len() ).toBe( 1 );
                expect( suppressed.results[ 1 ].id ).toBe( second.id );
                expect( variables.deliveries.getPage().results.len() ).toBe( 3 );
                var counts = variables.deliveries.stateCounts( filter );
                expect( counts.len() ).toBe( 2 );
                expect( counts[ 1 ].channel ).toBe( "database" );
                expect( counts[ 1 ].state ).toBe( "suppressed" );
                expect( counts[ 1 ].total ).toBe( 1 );
                expect( counts[ 2 ].channel ).toBe( "push" );
                expect( counts[ 2 ].state ).toBe( "queued" );
                expect( counts[ 2 ].total ).toBe( 1 );
            } );
            it( "imports acceptance and uncertainty without generating attempts or making them due", () => {
                var intent = {
                    eventId: variables.event.id,
                    recipientType: "User",
                    recipientId: "migrated",
                    channel: "email",
                    routingData: { sourceId: "old-work" },
                    routingHash: "import-routing"
                };
                var history = {
                    state: "accepted",
                    attemptCount: 3,
                    createdDate: dateAdd( "d", -5, variables.clock ),
                    settledDate: dateAdd( "d", -4, variables.clock ),
                    providerReference: "verified-old-receipt",
                    reason: "imported"
                };
                var accepted = variables.deliveries.importDelivery( intent, history );
                expect( accepted.state ).toBe( "accepted" );
                expect( accepted.attemptCount ).toBe( 3 );
                expect( dateCompare( accepted.createdDate, history.createdDate, "s" ) ).toBe( 0 );
                expect( dateCompare( accepted.settledDate, history.settledDate, "s" ) ).toBe( 0 );
                expect( variables.deliveries.claim( accepted.id ).status ).toBe( "accepted" );
                expect( variables.deliveries.attempts( accepted.id ).len() ).toBe( 0 );
                history.state = "queued";
                expect( variables.deliveries.importDelivery( intent, history ).state ).toBe( "accepted" );
                intent.recipientId = "uncertain";
                history.state = "ambiguous";
                history.providerReference = "";
                var ambiguous = variables.deliveries.importDelivery( intent, history );
                expect( variables.deliveries.claim( ambiguous.id ).status ).toBe( "ambiguous" );
                expect( variables.deliveries.due().len() ).toBe( 0 );
                expect( variables.deliveries.attempts( ambiguous.id ).len() ).toBe( 0 );
                expect( () => variables.deliveries.importDelivery( intent, { state: "accepted", createdDate: now() } ) ).toThrow(
                    type = "Megaphone.Delivery.InvalidImport"
                );
            } );
            it( "rolls back work with the originating event transaction", () => {
                var work = enqueue();
                transactionRollback();
                expect( isNull( variables.deliveries.find( work.id ) ) ).toBeTrue();
                expect( isNull( variables.events.find( variables.event.id ) ) ).toBeTrue();
            } );
            it( "fences duplicate jobs and preserves accepted provider evidence", () => {
                var work = enqueue();
                var started = variables.deliveries.claim( work.id );
                expect( started.status ).toBe( "ready" );
                expect( variables.deliveries.claim( work.id ).status ).toBe( "busy" );
                expect( variables.deliveries.startTransport( work.id, "foreign-token" ) ).toBeFalse();
                expect( variables.deliveries.startTransport( work.id, started.token ) ).toBeTrue();
                expect( variables.deliveries.startTransport( work.id, started.token ) ).toBeFalse();
                expect(
                    variables.deliveries.complete(
                        id = work.id,
                        token = started.token,
                        outcome = "accepted",
                        providerReference = "provider-123"
                    )
                ).toBeTrue();
                expect( variables.deliveries.claim( work.id ).status ).toBe( "accepted" );
                expect( variables.deliveries.complete( id = work.id, token = started.token, outcome = "retryable" ) ).toBeFalse();
                var attempts = variables.deliveries.attempts( work.id );
                expect( attempts.len() ).toBe( 1 );
                expect( attempts[ 1 ].providerReference ).toBe( "provider-123" );
                expect( attempts[ 1 ].outcome ).toBe( "accepted" );
            } );
            it( "imports verified acceptance without sending and fences a subsequently confirmed older receipt", () => {
                var imported = enqueue();
                expect(
                    variables.deliveries.reconcileAccepted( imported.id, ( work ) => {
                        return { "accepted": false };
                    } )
                ).toBeFalse();
                expect( variables.deliveries.find( imported.id ).state ).toBe( "queued" );
                expect(
                    variables.deliveries.reconcileAccepted( imported.id, ( work ) => {
                        return { "accepted": true, "providerReference": "previous-owner-receipt" };
                    } )
                ).toBeTrue();
                expect( variables.deliveries.find( imported.id ).transportCount ).toBe( 0 );
                expect( variables.deliveries.claim( imported.id ).status ).toBe( "accepted" );
                var pending = enqueue( device = "receipt-device" );
                var claimed = variables.deliveries.claim( pending.id );
                expect(
                    variables.deliveries.reconcileAccepted( pending.id, ( work ) => {
                        return { "accepted": true, "providerReference": "late-accepted-receipt" };
                    } )
                ).toBeTrue();
                expect( variables.deliveries.startTransport( pending.id, claimed.token ) ).toBeFalse();
                expect( variables.deliveries.complete( id = pending.id, token = claimed.token, outcome = "retryable" ) ).toBeFalse();
                expect( variables.deliveries.find( pending.id ).providerReference ).toBe( "late-accepted-receipt" );
            } );
            it( "reclaims work that expired before transport and blocks its previous token", () => {
                var work = enqueue( availableDate = variables.clock );
                var first = variables.deliveries.claim( id = work.id, clock = variables.clock, leaseSeconds = 1 );
                var later = dateAdd( "s", 2, variables.clock );
                var second = variables.deliveries.claim( id = work.id, clock = later );
                expect( second.status ).toBe( "ready" );
                expect( second.token ).notToBe( first.token );
                expect( variables.deliveries.startTransport( id = work.id, token = first.token, clock = later ) ).toBeFalse();
                expect( variables.deliveries.startTransport( id = work.id, token = second.token, clock = later ) ).toBeTrue();
                expect( variables.deliveries.attempts( work.id )[ 1 ].outcome ).toBe( "retryable" );
            } );
            it( "keeps expired started transport ambiguous and records late acceptance without another send", () => {
                var work = enqueue( availableDate = variables.clock );
                var started = variables.deliveries.claim( id = work.id, clock = variables.clock, leaseSeconds = 1 );
                expect(
                    variables.deliveries.startTransport( id = work.id, token = started.token, clock = variables.clock )
                ).toBeTrue();
                var later = dateAdd( "s", 2, variables.clock );
                expect( variables.deliveries.claim( id = work.id, clock = later ).status ).toBe( "ambiguous" );
                expect( variables.deliveries.claim( id = work.id, clock = later ).status ).toBe( "ambiguous" );
                expect(
                    variables.deliveries.complete(
                        id = work.id,
                        token = started.token,
                        outcome = "accepted",
                        providerReference = "late-accepted",
                        clock = later
                    )
                ).toBeTrue();
                expect( variables.deliveries.find( work.id ).state ).toBe( "accepted" );
                expect( variables.deliveries.attempts( work.id ).len() ).toBe( 1 );
            } );
            it( "suppresses before I/O and rejects misleading suppression or acceptance", () => {
                var work = enqueue();
                var started = variables.deliveries.claim( work.id );
                expect( () => variables.deliveries.complete( id = work.id, token = started.token, outcome = "accepted" ) ).toThrow(
                    type = "Megaphone.Delivery.TransportNotStarted"
                );
                expect(
                    variables.deliveries.complete(
                        id = work.id,
                        token = started.token,
                        outcome = "suppressed",
                        reason = "preference-disabled"
                    )
                ).toBeTrue();
                expect( variables.deliveries.claim( work.id ).status ).toBe( "suppressed" );
                var second = enqueue( device = "second" );
                var next = variables.deliveries.claim( second.id );
                variables.deliveries.startTransport( second.id, next.token );
                expect( () => variables.deliveries.complete( id = second.id, token = next.token, outcome = "suppressed" ) ).toThrow(
                    type = "Megaphone.Delivery.TransportAlreadyStarted"
                );
            } );
            it( "honors retry scheduling and bounds attempts", () => {
                var work = enqueue( availableDate = variables.clock );
                var first = variables.deliveries.claim( id = work.id, clock = variables.clock, maxAttempts = 2 );
                variables.deliveries.startTransport( id = work.id, token = first.token, clock = variables.clock );
                var later = dateAdd( "s", 30, variables.clock );
                variables.deliveries.complete(
                    id = work.id,
                    token = first.token,
                    outcome = "retryable",
                    retryDate = later,
                    clock = variables.clock
                );
                expect( variables.deliveries.claim( id = work.id, clock = variables.clock ).status ).toBe( "deferred" );
                expect( variables.deliveries.due( clock = variables.clock ).len() ).toBe( 0 );
                expect( variables.deliveries.due( clock = later ).len() ).toBe( 1 );
                var second = variables.deliveries.claim( id = work.id, clock = later, maxAttempts = 2 );
                variables.deliveries.startTransport( id = work.id, token = second.token, clock = later );
                variables.deliveries.complete(
                    id = work.id,
                    token = second.token,
                    outcome = "retryable",
                    retryDate = later,
                    clock = later
                );
                expect( variables.deliveries.claim( id = work.id, clock = later, maxAttempts = 2 ).status ).toBe( "exhausted" );
                expect( variables.deliveries.find( work.id ).state ).toBe( "permanent" );
                expect( variables.deliveries.attempts( work.id ).len() ).toBe( 2 );
            } );
            it( "recovers expired jobs without requeueing transport with uncertain acceptance", () => {
                var first = enqueue( availableDate = variables.clock );
                var second = enqueue( device = "second", availableDate = variables.clock );
                variables.deliveries.claim( id = first.id, clock = variables.clock, leaseSeconds = 1 );
                var sending = variables.deliveries.claim( id = second.id, clock = variables.clock, leaseSeconds = 1 );
                variables.deliveries.startTransport( id = second.id, token = sending.token, clock = variables.clock );
                var later = dateAdd( "s", 2, variables.clock );
                expect( variables.deliveries.recoverExpired( limit = 1, clock = later ) ).toBe( 1 );
                expect( variables.deliveries.recoverExpired( clock = later ) ).toBe( 1 );
                expect( variables.deliveries.recoverExpired( clock = later ) ).toBe( 0 );
                expect( variables.deliveries.find( first.id ).state ).toBe( "retryable" );
                expect( variables.deliveries.find( second.id ).state ).toBe( "ambiguous" );
                var due = variables.deliveries.due( clock = later );
                expect( due.len() ).toBe( 1 );
                expect( due[ 1 ].id ).toBe( first.id );
            } );
            it( "prunes terminal attempt diagnostics without losing acceptance or ambiguous evidence", () => {
                var first = enqueue();
                var started = variables.deliveries.claim( first.id );
                variables.deliveries.startTransport( first.id, started.token );
                variables.deliveries.complete(
                    id = first.id,
                    token = started.token,
                    outcome = "accepted",
                    providerReference = "accepted-receipt"
                );
                var second = enqueue( device = "second" );
                var sending = variables.deliveries.claim( second.id );
                variables.deliveries.startTransport( second.id, sending.token );
                variables.deliveries.complete(
                    id = second.id,
                    token = sending.token,
                    outcome = "ambiguous",
                    reason = "connection-lost"
                );
                expect( variables.deliveries.pruneAttempts( beforeDate = dateAdd( "d", 1, now() ) ) ).toBe( 1 );
                expect( variables.deliveries.attempts( first.id ).len() ).toBe( 0 );
                expect( variables.deliveries.find( first.id ).providerReference ).toBe( "accepted-receipt" );
                expect( enqueue().id ).toBe( first.id );
                expect( variables.deliveries.claim( first.id ).status ).toBe( "accepted" );
                expect( variables.deliveries.attempts( second.id ).len() ).toBe( 1 );
                expect( variables.deliveries.find( second.id ).state ).toBe( "ambiguous" );
            } );
            it( "preserves attempt diagnostics when a terminal delivery is reopened for recovery", () => {
                var work = enqueue();
                var lease = variables.deliveries.claim( work.id );
                variables.deliveries.startTransport( work.id, lease.token );
                variables.deliveries.complete(
                    id = work.id,
                    token = lease.token,
                    outcome = "permanent",
                    providerReference = "definite-rejection"
                );
                var prior = variables.deliveries.find( work.id );
                variables.deliveries.requestRecovery(
                    work.id,
                    createUUID(),
                    "operator",
                    variables.deliveries.recoveryVersion( prior ),
                    ( row ) => {
                        return { status: "ready" };
                    },
                    new tests.resources.DurableQueueFixture()
                );
                expect( variables.deliveries.pruneAttempts( beforeDate = dateAdd( "d", 1, now() ) ) ).toBe( 0 );
                expect( variables.deliveries.attempts( work.id ).len() ).toBe( 1 );
                expect( variables.deliveries.find( work.id ).state ).toBe( "queued" );
                expect( variables.deliveries.recoveryHistory( work.id ).results[ 1 ].priorProviderReference ).toBe( "definite-rejection" );
            } );
            it( "expires resolved events beyond the replay window while preserving pending and ambiguous work", () => {
                var past = dateAdd( "d", -400, variables.clock );
                variables.event = historicalEvent( "resolved" );
                var resolvedEvent = variables.event.id;
                var first = enqueue( availableDate = past );
                var claimed = variables.deliveries.claim( id = first.id, clock = past );
                variables.deliveries.startTransport( id = first.id, token = claimed.token, clock = past );
                variables.deliveries.complete(
                    id = first.id,
                    token = claimed.token,
                    outcome = "accepted",
                    clock = past
                );
                variables.event = historicalEvent( "pending" );
                var pendingEvent = variables.event.id;
                var pending = enqueue( availableDate = past );
                variables.event = historicalEvent( "ambiguous" );
                var ambiguousEvent = variables.event.id;
                var ambiguous = enqueue( availableDate = past );
                var unknown = variables.deliveries.claim( id = ambiguous.id, clock = past );
                variables.deliveries.startTransport( id = ambiguous.id, token = unknown.token, clock = past );
                variables.deliveries.complete(
                    id = ambiguous.id,
                    token = unknown.token,
                    outcome = "ambiguous",
                    clock = past
                );
                var retired = [];
                expect(
                    variables.deliveries.pruneResolvedEvents(
                        eventsBefore = dateAdd( "d", -365, variables.clock ),
                        deliveriesBefore = dateAdd( "d", -90, variables.clock ),
                        limit = 1,
                        beforePrune = ( event, deliveries ) => {
                            expect( event.id ).toBe( resolvedEvent );
                            expect( deliveries.len() ).toBe( 1 );
                            expect( deliveries[ 1 ].id ).toBe( first.id );
                            expect( deliveries[ 1 ].state ).toBe( "accepted" );
                            expect( isNull( variables.deliveries.find( first.id ) ) ).toBeFalse();
                            retired.append( event.id );
                        }
                    )
                ).toBe( 1 );
                expect( retired ).toBe( [ resolvedEvent ] );
                expect( isNull( variables.events.find( resolvedEvent ) ) ).toBeTrue();
                expect( isNull( variables.deliveries.find( first.id ) ) ).toBeTrue();
                expect( variables.deliveries.attempts( first.id ).len() ).toBe( 0 );
                expect( isNull( variables.events.find( pendingEvent ) ) ).toBeFalse();
                expect( isNull( variables.events.find( ambiguousEvent ) ) ).toBeFalse();
                expect( variables.deliveries.find( pending.id ).state ).toBe( "queued" );
                expect( variables.deliveries.find( ambiguous.id ).state ).toBe( "ambiguous" );
                expect(
                    variables.deliveries.pruneResolvedEvents(
                        eventsBefore = dateAdd( "d", -365, variables.clock ),
                        deliveriesBefore = dateAdd( "d", -90, variables.clock )
                    )
                ).toBe( 0 );
            } );
            it( "retains an old event and recovery evidence until reopened work settles again", () => {
                variables.event = historicalEvent( "reopened" );
                var eventId = variables.event.id;
                var past = dateAdd( "d", -400, variables.clock );
                var work = enqueue( availableDate = past );
                var lease = variables.deliveries.claim( id = work.id, clock = past );
                variables.deliveries.startTransport( id = work.id, token = lease.token, clock = past );
                variables.deliveries.complete(
                    id = work.id,
                    token = lease.token,
                    outcome = "permanent",
                    providerReference = "historical-rejection",
                    clock = past
                );
                var recovered = variables.deliveries.requestRecovery(
                    work.id,
                    createUUID(),
                    "operator",
                    variables.deliveries.recoveryVersion( variables.deliveries.find( work.id ) ),
                    ( row ) => {
                        return { status: "ready" };
                    },
                    new tests.resources.DurableQueueFixture()
                );
                expect( recovered.status ).toBe( "saved" );
                expect(
                    variables.deliveries.pruneResolvedEvents(
                        eventsBefore = dateAdd( "d", -365, variables.clock ),
                        deliveriesBefore = dateAdd( "d", -90, variables.clock )
                    )
                ).toBe( 0 );
                expect( variables.events.find( eventId ).id ).toBe( eventId );
                expect( variables.deliveries.attempts( work.id ).len() ).toBe( 1 );
                expect( variables.deliveries.recoveryHistory( work.id ).results.len() ).toBe( 1 );
                var next = variables.deliveries.claim( work.id );
                variables.deliveries.complete( id = work.id, token = next.token, outcome = "suppressed" );
                expect(
                    variables.deliveries.pruneResolvedEvents(
                        eventsBefore = dateAdd( "d", -365, variables.clock ),
                        deliveriesBefore = dateAdd( "d", -90, variables.clock )
                    )
                ).toBe( 0 );
                expect(
                    variables.deliveries.pruneResolvedEvents(
                        eventsBefore = dateAdd( "d", -365, variables.clock ),
                        deliveriesBefore = dateAdd( "d", 1, now() )
                    )
                ).toBe( 1 );
                expect( isNull( variables.events.find( eventId ) ) ).toBeTrue();
                expect( variables.deliveries.recoveryHistory( work.id ).results.len() ).toBe( 0 );
            } );
            it( "allows one device to fail without blocking another", () => {
                var first = enqueue();
                var second = enqueue( device = "second" );
                var rejected = variables.deliveries.claim( first.id );
                variables.deliveries.complete(
                    id = first.id,
                    token = rejected.token,
                    outcome = "permanent",
                    reason = "subscription-expired"
                );
                var sent = variables.deliveries.claim( second.id );
                expect( sent.status ).toBe( "ready" );
                variables.deliveries.startTransport( second.id, sent.token );
                variables.deliveries.complete( id = second.id, token = sent.token, outcome = "accepted" );
                expect( variables.deliveries.find( first.id ).state ).toBe( "permanent" );
                expect( variables.deliveries.find( second.id ).state ).toBe( "accepted" );
            } );
        } );
    }

    private struct function historicalEvent( required string label ) {
        return variables.events.record(
            namespace = "test",
            eventKey = arguments.label & createUUID(),
            version = 1,
            type = "submitted",
            payload = {},
            payloadHash = "history",
            createdDate = dateAdd( "d", -400, variables.clock )
        );
    }

    private struct function enqueue(
        string device = "first",
        string channel = "push",
        string recipient = "user",
        string initialState = "queued",
        string routingHash = "routing",
        date availableDate = now()
    ) {
        return variables.deliveries.enqueue(
            eventId = variables.event.id,
            recipientType = "User",
            recipientId = arguments.recipient,
            channel = arguments.channel,
            deviceId = arguments.device,
            routingData = { "subjectId": "audition" },
            routingHash = arguments.routingHash,
            initialState = arguments.initialState,
            availableDate = arguments.availableDate
        );
    }

}
