component extends="tests.resources.ModuleIntegrationSpec" {

    function beforeAll() {
        super.beforeAll();
        var binder = getWireBox().getBinder();
        binder.map( "QueueNotification" ).to( "tests.resources.QueueNotification" );
        binder
            .map( "QueueNotifiableResolver" )
            .to( "tests.resources.QueueNotifiableResolver" )
            .asSingleton();
        binder
            .map( "QueueEligibilityPolicy" )
            .to( "tests.resources.QueueEligibilityPolicy" )
            .asSingleton();
        var settings = getController().getSetting( "moduleSettings" ).megaphone;
        variables.savedQueueSettings = duplicate( settings.queue );
        settings.queue.notifiableResolver = "QueueNotifiableResolver";
        settings.queue.eligibilityPolicy = "QueueEligibilityPolicy";
        variables.service = getWireBox().getInstance( "NotificationService@megaphone" );
        variables.savedChannels = structCopy( variables.service.getChannels() );
        variables.deliveries = getWireBox().getInstance( "NotificationDeliveryService@megaphone" );
        variables.resolver = getWireBox().getInstance( "QueueNotifiableResolver" );
        variables.policy = getWireBox().getInstance( "QueueEligibilityPolicy" );
    }

    /** Restores module queue settings so this bundle does not change later bundles' startup assertions. */
    public void function afterAll() {
        getController().getSetting( "moduleSettings" ).megaphone.queue = variables.savedQueueSettings;
        variables.service.setChannels( variables.savedChannels );
        super.afterAll();
    }

    function run() {
        describe( "Megaphone notification planning and registered-provider dispatch", () => {
            beforeEach( () => {
                variables.owner = new tests.resources.InboxRecipient();
                variables.resolver.register( variables.owner );
                variables.policy.setStatus( "ready" );
                variables.options = { "namespace": "queue-spec", "eventKey": createUUID(), "version": 1 };
                variables.service.registerChannels( { "database": { "provider": "DatabaseProvider@megaphone", "properties": {} } } );
                getController().getSetting( "moduleSettings" ).megaphone.queue.queueAdapter = "";
            } );
            it( "binds storage settings during actual module activation", () => {
                var stores = {
                    "EventStore": "megaphone_events",
                    "DeliveryStore": "megaphone_deliveries",
                    "PreferenceStore": "megaphone_preferences",
                    "SubscriptionStore": "megaphone_subscriptions"
                };
                for ( var name in stores ) {
                    var store = getWireBox().getInstance( name & "@megaphone" );
                    expect( store.getTableName() ).toBe( stores[ name ] );
                    expect( store.getQueryOptions().datasource ).toBe( "megaphone" );
                    expect( isCustomFunction( store.setProperties ?: "" ) ).toBeFalse();
                }
            } );
            it( "plans without writes and preserves a serialized audience and disabled channels", () => {
                var plan = variables.service.plan(
                    variables.owner,
                    "QueueNotification",
                    { "message": "snapshot", "choices": { "database": false } },
                    variables.options
                );
                expect( variables.deliveries.getDueDeliveries() ).toBeEmpty();
                var restored = new megaphone.models.NotificationPlan().populateFromMemento(
                    deserializeJSON( serializeJSON( plan.getMemento() ) )
                );
                var publication = variables.service.queuePlan( restored );
                expect( publication.getEvent().getCreated() ).toBeTrue();
                expect( publication.getDeliveries()[ 1 ].getState() ).toBe( "suppressed" );
                expect( publication.getDeliveries()[ 1 ].getNotifiableId() ).toBe( variables.owner.getNotifiableId() );
                expect( variables.deliveries.dispatch( publication.getDeliveries()[ 1 ].getId() ).getStatus() ).toBe( "suppressed" );
            } );
            it( "rolls back events and work when queue insertion fails", () => {
                var adapter = new tests.resources.DurableQueueFixture( true );
                getController().getSetting( "moduleSettings" ).megaphone.queue.queueAdapter = adapter;
                expect( () => variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    {},
                    variables.options
                ) ).toThrow( "QueueFixtureUnavailable" );
                var queued = adapter.getDeliveries()[ 1 ];
                expect( isNull( variables.deliveries.getDelivery( queued.id ) ) ).toBeTrue();
                expect( isNull( variables.deliveries.getEvent( queued.eventId ) ) ).toBeTrue();
            } );
            it( "retains cutoff decisions across serialized plans and admits equality", () => {
                var cutoff = now();
                var options = duplicate( variables.options );
                options.admitAfter = cutoff;
                options.occurredAt = dateAdd( "s", -1, cutoff );
                var old = variables.service.plan(
                    variables.owner,
                    "QueueNotification",
                    {},
                    options
                );
                var restored = new megaphone.models.NotificationPlan().populateFromMemento(
                    deserializeJSON( serializeJSON( old.getMemento() ) )
                );
                expect(
                    variables.service
                        .queuePlan( restored )
                        .getEvent()
                        .getExpired()
                ).toBeTrue();
                options.occurredAt = cutoff;
                expect(
                    variables.service
                        .queue(
                            variables.owner,
                            "QueueNotification",
                            {},
                            options
                        )
                        .getEvent()
                        .getCreated()
                ).toBeTrue();
            } );
            it( "reconstructs a directly constructed notification instance", () => {
                var notification = new tests.resources.QueueNotification().populate( { "message": "constructed" } );
                var publication = variables.service.queue(
                    variables.owner,
                    notification,
                    {},
                    variables.options
                );
                var id = publication.getDeliveries()[ 1 ].getId();
                expect( variables.deliveries.dispatch( id ).getStatus() ).toBe( "accepted" );
                expect(
                    getWireBox()
                        .getInstance( "DatabaseNotificationService@megaphone" )
                        .getNotification( variables.owner, id )
                        .getData()
                        .message
                ).toBe( "constructed" );
            } );
            it( "accepts populated notification instances and preserves two provider instances", () => {
                variables.service.registerChannels( {
                    "one": { "provider": "DatabaseProvider@megaphone", "properties": {} },
                    "two": { "provider": "DatabaseProvider@megaphone", "properties": {} }
                } );
                var notification = getWireBox().getInstance( "QueueNotification" );
                var published = variables.service.queue(
                    variables.owner,
                    notification,
                    { "channelNames": [ "one", "two" ], "message": "instance" },
                    variables.options
                );
                expect( published.getDeliveries().len() ).toBe( 2 );
                for ( var delivery in published.getDeliveries() ) {
                    expect( variables.deliveries.dispatch( delivery.getId() ).getStatus() ).toBe( "accepted" );
                }
            } );
            it( "dispatches through the database provider once with explicit acceptance", () => {
                var publication = variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    { "message": "stored" },
                    variables.options
                );
                var id = publication.getDeliveries()[ 1 ].getId();
                expect( variables.deliveries.dispatch( id ).getStatus() ).toBe( "accepted" );
                expect( variables.deliveries.dispatch( id ).getStatus() ).toBe( "accepted" );
                var entry = getWireBox()
                    .getInstance( "DatabaseNotificationService@megaphone" )
                    .getNotification( variables.owner, id );
                expect( entry.getData().message ).toBe( "stored" );
                expect( entry.getType() ).toBe( publication.getEvent().getType() );
                expect( variables.deliveries.getDelivery( id ).getTransportCount() ).toBe( 1 );
            } );
            it( "returns original work on replay without adding newly eligible recipients", () => {
                var properties = { "choices": { "database": false } };
                var first = variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    properties,
                    variables.options
                );
                var second = variables.service.queue(
                    [ variables.owner, new tests.resources.InboxRecipient() ],
                    "QueueNotification",
                    properties,
                    variables.options
                );
                expect( second.getEvent().getCreated() ).toBeFalse();
                expect( second.getEvent().getId() ).toBe( first.getEvent().getId() );
                expect( second.getDeliveries().len() ).toBe( 1 );
                expect( second.getDeliveries()[ 1 ].getState() ).toBe( "suppressed" );
            } );
            it( "supports renamed channels and rejects providers without durable capability", () => {
                variables.service.registerChannels( {
                    "inbox": { "provider": "DatabaseProvider@megaphone", "properties": {} },
                    "legacy": { "provider": "CustomNotificationProvider", "properties": {} }
                } );
                var publication = variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    { "channelNames": [ "inbox" ] },
                    variables.options
                );
                expect( publication.getDeliveries()[ 1 ].getChannelName() ).toBe( "inbox" );
                expect( variables.deliveries.dispatch( publication.getDeliveries()[ 1 ].getId() ).getStatus() ).toBe( "accepted" );
                expect( () => variables.service.plan( variables.owner, "QueueNotification", { "channelNames": [ "legacy" ] } ) ).toThrow( "Megaphone.Configuration.UnsupportedDurableProvider" );
            } );
            it( "rejects callbacks in stored properties and hashes key order deterministically", () => {
                expect( () => variables.service.plan(
                    variables.owner,
                    "QueueNotification",
                    {
                        "callback": () => {
                        }
                    }
                ) ).toThrow( "Megaphone.Notification.InvalidSnapshot" );
                var hasher = getWireBox().getInstance( "NotificationSnapshotHasher@megaphone" );
                expect( hasher.digest( { "a": 1, "b": 2 } ) ).toBe( hasher.digest( { "b": 2, "a": 1 } ) );
                expect( serializeJSON( hasher.snapshot( deserializeJSON( "[null]" ) ) ) ).toBe( "[null]" );
                expect( hasher.digest( [ 1, 2 ] ) ).notToBe( hasher.digest( [ 2, 1 ] ) );
            } );
            it( "holds current authorization before transport and preserves the send budget", () => {
                var publication = variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    {},
                    variables.options
                );
                var id = publication.getDeliveries()[ 1 ].getId();
                variables.policy.setStatus( "deferred" );
                expect( variables.deliveries.dispatch( id ).getStatus() ).toBe( "retryable" );
                expect( variables.deliveries.getDelivery( id ).getTransportCount() ).toBe( 0 );
            } );
            it( "does not send after preparation loses its lease", () => {
                var store = getWireBox().getInstance( "DeliveryStore@megaphone" );
                variables.service.registerChannels( {
                    "fixture": {
                        "provider": "tests.resources.DurableProviderFixture",
                        "properties": {
                            "onPrepare": ( delivery ) => store.recoverExpired( clock = dateAdd( "s", 120, now() ) )
                        }
                    }
                } );
                var work = variables.service
                    .queue(
                        variables.owner,
                        "QueueNotification",
                        { "channelNames": [ "fixture" ] },
                        variables.options
                    )
                    .getDeliveries()[ 1 ];
                expect( variables.deliveries.dispatch( work.getId() ).getStatus() ).toBe( "superseded" );
                expect( variables.service.getChannel( "fixture" ).getSends() ).toBe( 0 );
                expect( variables.deliveries.getDelivery( work.getId() ).getTransportCount() ).toBe( 0 );
            } );
            it( "does not spend transport allowance on preparation failures", () => {
                variables.service.registerChannels( {
                    "fixture": {
                        "provider": "tests.resources.DurableProviderFixture",
                        "properties": { "failPreparation": true }
                    }
                } );
                var work = variables.service
                    .queue(
                        variables.owner,
                        "QueueNotification",
                        { "channelNames": [ "fixture" ] },
                        variables.options
                    )
                    .getDeliveries()[ 1 ];
                expect( variables.deliveries.dispatch( work.getId() ).getStatus() ).toBe( "retryable" );
                expect( variables.deliveries.getDelivery( work.getId() ).getTransportCount() ).toBe( 0 );
            } );
            it( "does not replay ambiguous provider acceptance", () => {
                variables.service.registerChannels( {
                    "fixture": {
                        "provider": "tests.resources.DurableProviderFixture",
                        "properties": { "failSending": true }
                    }
                } );
                var publication = variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    { "channelNames": [ "fixture" ] },
                    variables.options
                );
                var id = publication.getDeliveries()[ 1 ].getId();
                expect( variables.deliveries.dispatch( id ).getStatus() ).toBe( "ambiguous" );
                expect( variables.deliveries.dispatch( id ).getStatus() ).toBe( "ambiguous" );
                expect( variables.service.getChannel( "fixture" ).getSends() ).toBe( 1 );
            } );
            it( "rechecks eligibility after provider preparation", () => {
                var policy = variables.policy;
                variables.service.registerChannels( {
                    "fixture": {
                        "provider": "tests.resources.DurableProviderFixture",
                        "properties": { "onPrepare": ( delivery ) => policy.setStatus( "suppressed" ) }
                    }
                } );
                var publication = variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    { "channelNames": [ "fixture" ] },
                    variables.options
                );
                expect( variables.deliveries.dispatch( publication.getDeliveries()[ 1 ].getId() ).getStatus() ).toBe( "suppressed" );
                expect( variables.service.getChannel( "fixture" ).getSends() ).toBe( 0 );
            } );
        } );
    }

}
