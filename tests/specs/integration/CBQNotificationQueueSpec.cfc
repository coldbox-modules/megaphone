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
        binder.map( "QueueOutcomeProvider" ).to( "tests.resources.QueueOutcomeProvider" );
        variables.settings = getController().getSetting( "moduleSettings" ).megaphone;
        variables.bootAdapter = variables.settings.queue.queueAdapter;
        variables.service = getWireBox().getInstance( "NotificationService@megaphone" );
        variables.savedChannels = structCopy( variables.service.getChannels() );
        variables.deliveries = getWireBox().getInstance( "NotificationDeliveryService@megaphone" );
        variables.config = getWireBox().getInstance( "Config@cbq" );
        variables.resolver = getWireBox().getInstance( "QueueNotifiableResolver" );
        variables.policy = getWireBox().getInstance( "QueueEligibilityPolicy" );
    }

    /** Restores registered channels so later bundles see their configured database and synchronous providers. */
    public void function afterAll() {
        variables.service.setChannels( variables.savedChannels );
        super.afterAll();
    }


    function run() {
        describe( "Bundled cbq notification queue", () => {
            beforeEach( () => {
                variables.savedSettings = duplicate( variables.settings.queue );
                variables.savedConnection = variables.config.getDefaultConnectionName();
                variables.settings.queue.queueAdapter = "CBQNotificationQueue@megaphone";
                variables.settings.queue.defaultConnection = "default";
                variables.settings.queue.notifiableResolver = "QueueNotifiableResolver";
                variables.settings.queue.eligibilityPolicy = "QueueEligibilityPolicy";
                variables.owner = new tests.resources.InboxRecipient();
                variables.resolver.register( variables.owner );
                variables.policy.setStatus( "ready" );
                variables.options = { "namespace": "cbq-spec", "eventKey": createUUID() };
                variables.service.registerChannels( { "database": { "provider": "DatabaseProvider@megaphone", "properties": {} } } );
            } );
            afterEach( () => {
                variables.settings.queue = variables.savedSettings;
                variables.config.setDefaultConnectionName( variables.savedConnection );
            } );

            it( "uses the application cbq configuration without adding connections or workers", () => {
                expect( variables.bootAdapter ).toBe( "CBQNotificationQueue@megaphone" );
                expect(
                    variables.config
                        .getConnection( "default" )
                        .getProvider()
                        .getProperties()
                        .datasource
                ).toBe( "megaphone" );
                expect( variables.config.getWorkerPools() ).toBeEmpty();
                expect( getWireBox().getInstance( "CBQNotificationQueue@megaphone" ) ).toBeInstanceOf( "megaphone.models.CBQNotificationQueue" );
                expect( getWireBox().getInstance( "CBQNotificationQueue@megaphone" ) ).toBeInstanceOf( "megaphone.models.Interfaces.INotificationQueue" );
            } );
            it( "queues only a delivery ID and runs the serialized job idempotently", () => {
                var publication = variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    { "message": "cbq" },
                    variables.options
                );
                var rows = jobs();
                expect( rows.recordCount ).toBe( 1 );
                var payload = deserializeJSON( rows.payload[ 1 ] );
                expect( payload.properties.keyArray() ).toBe( [ "deliveryId" ] );
                expect( payload.properties.deliveryId ).toBe( publication.getDeliveries()[ 1 ].getId() );
                expect( payload.maxAttempts ).toBe( 1 );
                expect( isNull( payload.timeout ) ).toBeTrue();
                var job = deserializeJob( rows.payload[ 1 ] );
                expect( job.handle() ).toBe( "accepted" );
                expect( job.handle() ).toBe( "accepted" );
                expect( variables.deliveries.getDelivery( payload.properties.deliveryId ).getTransportCount() ).toBe(
                    1
                );
                expect(
                    getWireBox()
                        .getInstance( "DatabaseNotificationService@megaphone" )
                        .getNotification( variables.owner, payload.properties.deliveryId )
                        .getData()
                        .message
                ).toBe( "cbq" );
            } );
            it( "keeps delayed jobs and replay from expanding the queue", () => {
                variables.options.availableDate = dateAdd( "s", 120, now() );
                var first = variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    {},
                    variables.options
                );
                var second = variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    {},
                    variables.options
                );
                expect( jobs().recordCount ).toBe( 1 );
                expect( jobs().availableDate[ 1 ] - jobs().createdDate[ 1 ] ).toBeGTE( 118 );
                expect( first.getEvent().getId() ).toBe( second.getEvent().getId() );
            } );
            it( "rolls back cbq insertion together with publication", () => {
                var id = "";
                transaction {
                    var publication = variables.service.queue(
                        variables.owner,
                        "QueueNotification",
                        {},
                        variables.options
                    );
                    id = publication.getDeliveries()[ 1 ].getId();
                    expect( jobs().recordCount ).toBe( 1 );
                    transactionRollback();
                }
                expect( jobs().recordCount ).toBe( 0 );
                expect( isNull( variables.deliveries.getDelivery( id ) ) ).toBeTrue();
            } );
            it( "rolls back publication when the cbq connection is unavailable", () => {
                variables.settings.queue.defaultConnection = "missing-notification-connection";
                expect( () => variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    {},
                    variables.options
                ) ).toThrow( "cbq.MissingQueueConnection" );
                expect( variables.deliveries.getDueDeliveries() ).toBeEmpty();
                expect( jobs().recordCount ).toBe( 0 );
            } );
            it( "uses a registered non-database provider on cbq's default connection", () => {
                var provider = getWireBox().getInstance( "tests.resources.RegisteredQueueProvider" );
                variables.config.registerConnection(
                    name = "registered-notifications",
                    provider = provider,
                    defaultQueue = "alerts"
                );
                variables.config.setDefaultConnectionName( "registered-notifications" );
                variables.settings.queue.defaultConnection = "";
                var publication = variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    {},
                    variables.options
                );
                var entries = provider.getEntries();
                expect( entries.len() ).toBe( 1 );
                expect( entries[ 1 ].queueName ).toBe( "alerts" );
                expect( jobs().recordCount ).toBe( 0 );
                var payload = deserializeJSON( entries[ 1 ].payload );
                expect( payload.properties.keyArray() ).toBe( [ "deliveryId" ] );
                expect( payload.properties.deliveryId ).toBe( publication.getDeliveries()[ 1 ].getId() );
                expect( payload.maxAttempts ).toBe( 1 );
                expect( provider.deserializeJob( entries[ 1 ].payload, 1 ).handle() ).toBe( "accepted" );
            } );
            it( "delegates inline execution to a registered synchronous provider", () => {
                variables.config.registerConnection(
                    name = "notification-sync",
                    provider = "SyncProvider@cbq",
                    defaultQueue = "notifications"
                );
                var pool = variables.config.registerWorkerPool(
                    name = "notification-sync-test",
                    connectionName = "notification-sync",
                    queue = "notifications",
                    maxAttempts = 1
                );
                try {
                    variables.settings.queue.defaultConnection = "notification-sync";
                    var publication = variables.service.queue(
                        variables.owner,
                        "QueueNotification",
                        {},
                        variables.options
                    );
                    var work = variables.deliveries.getDelivery( publication.getDeliveries()[ 1 ].getId() );
                    expect( work.getState() ).toBe( "accepted" );
                    expect( work.getTransportCount() ).toBe( 1 );
                    expect( jobs().recordCount ).toBe( 0 );
                } finally {
                    pool.shutdown( true );
                }
            } );
            it( "uses synchronous provider backoff and stops at Megaphone's transport budget", () => {
                var provider = outcomeProvider( "retryable" );
                variables.settings.queue.maxAttempts = 2;
                variables.settings.queue.retrySeconds = 1;
                variables.config.registerConnection(
                    name = "notification-sync-retry",
                    provider = "SyncProvider@cbq",
                    defaultQueue = "notifications"
                );
                var pool = variables.config.registerWorkerPool(
                    name = "notification-sync-retry-test",
                    connectionName = "notification-sync-retry",
                    queue = "notifications",
                    maxAttempts = 1
                );
                try {
                    variables.settings.queue.defaultConnection = "notification-sync-retry";
                    var publication = variables.service.queue(
                        variables.owner,
                        "QueueNotification",
                        {},
                        variables.options
                    );
                    var work = variables.deliveries.getDelivery( publication.getDeliveries()[ 1 ].getId() );
                    expect( work.getTransportCount() ).toBe( 2 );
                    expect( provider.getSendCount() ).toBe( 2 );
                    expect( work.getState() ).toBe( "permanent" );
                } finally {
                    pool.shutdown( true );
                }
            } );
            it( "supports a renamed queue and connection", () => {
                variables.config.registerConnection(
                    name = "notification-test",
                    provider = "DBProvider@cbq",
                    properties = { "datasource": "megaphone" }
                );
                variables.service.queue(
                    notifiables = variables.owner,
                    notification = "QueueNotification",
                    properties = {},
                    options = variables.options,
                    connection = "notification-test",
                    queue = "custom-notifications"
                );
                expect(
                    queryExecute(
                        "SELECT COUNT(*) AS total FROM cbq_jobs WHERE queue='custom-notifications'",
                        {},
                        { "datasource": "megaphone" }
                    ).total[ 1 ]
                ).toBe( 1 );
            } );
            it( "uses configured defaults and lets a call override either route", () => {
                var provider = getWireBox().getInstance( "tests.resources.RegisteredQueueProvider" );
                var overrideProvider = getWireBox().getInstance( "tests.resources.RegisteredQueueProvider" );
                variables.config.registerConnection(
                    name = "module-default",
                    provider = provider,
                    defaultQueue = "cbq-default"
                );
                variables.config.registerConnection(
                    name = "call-connection",
                    provider = overrideProvider,
                    defaultQueue = "another-cbq-default"
                );
                variables.settings.queue.defaultConnection = "module-default";
                variables.settings.queue.defaultQueue = "module-queue";
                variables.service.queue( notifiables = variables.owner, notification = "QueueNotification" );
                expect( provider.getEntries()[ 1 ].queueName ).toBe( "module-queue" );
                variables.service.queue(
                    notifiables = variables.owner,
                    notification = "QueueNotification",
                    queue = "call-queue"
                );
                expect( provider.getEntries()[ 2 ].queueName ).toBe( "call-queue" );
                variables.service.queue(
                    notifiables = variables.owner,
                    notification = "QueueNotification",
                    connection = "call-connection"
                );
                expect( overrideProvider.getEntries()[ 1 ].queueName ).toBe( "module-queue" );
                variables.service.queue(
                    notifiables = variables.owner,
                    notification = "QueueNotification",
                    connection = "call-connection",
                    queue = "both-overrides"
                );
                expect( overrideProvider.getEntries()[ 2 ].queueName ).toBe( "both-overrides" );
                expect( jobs().recordCount ).toBe( 0 );
            } );
            it( "uses cbq defaults when only one route argument is supplied", () => {
                var provider = getWireBox().getInstance( "tests.resources.RegisteredQueueProvider" );
                variables.config.registerConnection(
                    name = "route-defaults",
                    provider = provider,
                    defaultQueue = "connection-default"
                );
                variables.service.queue(
                    notifiables = variables.owner,
                    notification = "QueueNotification",
                    connection = "route-defaults"
                );
                expect( provider.getEntries()[ 1 ].queueName ).toBe( "connection-default" );
                variables.settings.queue.defaultConnection = "route-defaults";
                variables.service.queue(
                    notifiables = variables.owner,
                    notification = new tests.resources.QueueNotification(),
                    queue = "call-queue"
                );
                expect( provider.getEntries()[ 2 ].queueName ).toBe( "call-queue" );
                expect( jobs().recordCount ).toBe( 0 );
            } );
            it( "keeps the selected connection and queue in a restored plan and allows handoff overrides", () => {
                var firstProvider = getWireBox().getInstance( "tests.resources.RegisteredQueueProvider" );
                var secondProvider = getWireBox().getInstance( "tests.resources.RegisteredQueueProvider" );
                variables.config.registerConnection(
                    name = "planned",
                    provider = firstProvider,
                    defaultQueue = "first-default"
                );
                variables.config.registerConnection(
                    name = "handoff",
                    provider = secondProvider,
                    defaultQueue = "second-default"
                );
                variables.settings.queue.defaultConnection = "missing-notification-connection";
                var plan = variables.service.plan(
                    notifiables = variables.owner,
                    notification = "QueueNotification",
                    options = variables.options,
                    connection = "planned",
                    queue = "saved-queue"
                );
                var saved = deserializeJSON( serializeJSON( plan.getMemento() ) );
                var restored = getWireBox().getInstance( "NotificationPlan@megaphone" ).populateFromMemento( saved );
                expect( restored.getQueueOptions() ).toBe( { "connection": "planned", "queue": "saved-queue" } );
                variables.service.queuePlan( restored );
                expect( firstProvider.getEntries()[ 1 ].queueName ).toBe( "saved-queue" );
                saved.event.eventKey = createUUID();
                restored.populateFromMemento( saved );
                variables.service.queuePlan( plan = restored, connection = "handoff", queue = "handoff-queue" );
                expect( secondProvider.getEntries()[ 1 ].queueName ).toBe( "handoff-queue" );
                variables.service.queuePlan( plan = restored, connection = "planned", queue = "another-queue" );
                expect( firstProvider.getEntries().len() ).toBe( 1 );
                expect( secondProvider.getEntries().len() ).toBe( 1 );
                structDelete( saved, "queueOptions" );
                restored.populateFromMemento( saved );
                expect( restored.getQueueOptions() ).toBeEmpty();
            } );
            it( "allows a custom adapter or explicit polling without cbq jobs", () => {
                var adapter = new tests.resources.DurableQueueFixture();
                expect( adapter ).toBeInstanceOf( "megaphone.models.Interfaces.INotificationQueue" );
                variables.settings.queue.queueAdapter = adapter;
                variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    {},
                    variables.options
                );
                expect( adapter.getDeliveries().len() ).toBe( 1 );
                expect( jobs().recordCount ).toBe( 0 );
                variables.settings.queue.queueAdapter = "";
                variables.options.eventKey = createUUID();
                variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    {},
                    variables.options
                );
                expect( jobs().recordCount ).toBe( 0 );
            } );
            it( "does not enqueue suppressed channels", () => {
                variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    { "choices": { "database": false } },
                    variables.options
                );
                expect( jobs().recordCount ).toBe( 0 );
            } );
            it( "reschedules a known retryable outcome at its saved availability date", () => {
                var provider = outcomeProvider( "retryable" );
                var publication = variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    {},
                    variables.options
                );
                var job = deserializeJob( jobs().payload[ 1 ] );
                expect( job.handle() ).toBe( "retryable" );
                expect( job.getIsReleased() ).toBeTrue();
                expect( job.getMaxAttempts() ).toBe( 2 );
                expect( job.getBackoff() ).toBeGTE( 28 );
                expect( jobs().recordCount ).toBe( 1 );
                expect( provider.getSendCount() ).toBe( 1 );
                expect(
                    variables.deliveries.getDelivery( publication.getDeliveries()[ 1 ].getId() ).getTransportCount()
                ).toBe( 1 );
            } );
            it( "reschedules deferred policy checks without consuming a transport", () => {
                var publication = variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    {},
                    variables.options
                );
                variables.policy.setStatus( "deferred" );
                var job = deserializeJob( jobs().payload[ 1 ] );
                expect( job.handle() ).toBe( "retryable" );
                expect( job.getIsReleased() ).toBeTrue();
                expect( jobs().recordCount ).toBe( 1 );
                expect(
                    variables.deliveries.getDelivery( publication.getDeliveries()[ 1 ].getId() ).getTransportCount()
                ).toBe( 0 );
            } );
            it( "waits for an active lease before scheduling a competing job", () => {
                var publication = variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    {},
                    variables.options
                );
                getWireBox()
                    .getInstance( "DeliveryStore@megaphone" )
                    .claim( publication.getDeliveries()[ 1 ].getId(), 120, 5 );
                var job = deserializeJob( jobs().payload[ 1 ] );
                expect( job.handle() ).toBe( "busy" );
                expect( job.getIsReleased() ).toBeTrue();
                var rows = jobs();
                expect( rows.recordCount ).toBe( 1 );
                expect( job.getBackoff() ).toBeGTE( 118 );
                expect(
                    variables.deliveries.getDelivery( publication.getDeliveries()[ 1 ].getId() ).getTransportCount()
                ).toBe( 0 );
            } );
            it( "does not reschedule ambiguous acceptance or a transport exception", () => {
                var provider = outcomeProvider( "ambiguous" );
                variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    {},
                    variables.options
                );
                expect( deserializeJob( jobs().payload[ 1 ] ).handle() ).toBe( "ambiguous" );
                expect( jobs().recordCount ).toBe( 1 );
                provider.setOutcome( "throw" );
                variables.options.eventKey = createUUID();
                variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    {},
                    variables.options
                );
                expect( deserializeJob( jobs().payload[ 2 ] ).handle() ).toBe( "ambiguous" );
                expect( jobs().recordCount ).toBe( 2 );
            } );
        } );
    }

    private query function jobs() {
        return queryExecute(
            "SELECT * FROM cbq_jobs WHERE queue='notifications' ORDER BY id",
            {},
            { "datasource": "megaphone" }
        );
    }
    private any function deserializeJob( required string payload ) {
        return variables.config
            .getConnection( variables.settings.queue.defaultConnection )
            .getProvider()
            .deserializeJob( arguments.payload, 1, 1 );
    }
    private any function outcomeProvider( required string status ) {
        variables.service.registerChannels( { "database": { "provider": "QueueOutcomeProvider", "properties": {} } } );
        var provider = variables.service.getChannel( "database" );
        provider.setOutcome( arguments.status );
        return provider;
    }

}
