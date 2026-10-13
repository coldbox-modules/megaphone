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
        variables.bootAdapter = variables.settings.durable.queueAdapter;
        variables.service = getWireBox().getInstance( "NotificationService@megaphone" );
        variables.deliveries = getWireBox().getInstance( "NotificationDeliveryService@megaphone" );
        variables.config = getWireBox().getInstance( "Config@cbq" );
        variables.resolver = getWireBox().getInstance( "QueueNotifiableResolver" );
        variables.policy = getWireBox().getInstance( "QueueEligibilityPolicy" );
    }

    function run() {
        describe( "Bundled cbq notification queue", () => {
            beforeEach( () => {
                variables.savedSettings = duplicate( variables.settings.durable );
                variables.settings.durable.queueAdapter = "CBQNotificationQueue@megaphone";
                variables.settings.durable.queueConnection = "default";
                variables.settings.durable.queueName = "notifications";
                variables.settings.durable.notifiableResolver = "QueueNotifiableResolver";
                variables.settings.durable.eligibilityPolicy = "QueueEligibilityPolicy";
                variables.owner = new tests.resources.InboxRecipient();
                variables.resolver.register( variables.owner );
                variables.policy.setStatus( "ready" );
                variables.options = { "namespace": "cbq-spec", "eventKey": createUUID() };
                variables.service.registerChannels( { "database": { "provider": "DatabaseProvider@megaphone", "properties": {} } } );
            } );
            afterEach( () => {
                variables.settings.durable = variables.savedSettings;
            } );

            it( "activates cbq with a bundled database connection and no synchronous-only workers", () => {
                expect( variables.bootAdapter ).toBe( "CBQNotificationQueue@megaphone" );
                expect(
                    variables.config
                        .getConnection( "default" )
                        .getProvider()
                        .getProperties()
                        .queryOptions
                        .datasource
                ).toBe( "megaphone" );
                expect( variables.config.getWorkerPools() ).toBeEmpty();
                expect( getWireBox().getInstance( "CBQNotificationQueue@megaphone" ) ).toBeInstanceOf( "megaphone.models.CBQNotificationQueue" );
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
                variables.settings.durable.queueConnection = "missing-notification-connection";
                expect( () => variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    {},
                    variables.options
                ) ).toThrow( "cbq.MissingQueueConnection" );
                expect( variables.deliveries.getDueDeliveries() ).toBeEmpty();
                expect( jobs().recordCount ).toBe( 0 );
            } );
            it( "supports a renamed queue and connection", () => {
                variables.config.registerConnection(
                    name = "notification-test",
                    provider = "DBProvider@cbq",
                    properties = { "datasource": "megaphone" }
                );
                variables.settings.durable.queueConnection = "notification-test";
                variables.settings.durable.queueName = "custom-notifications";
                variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    {},
                    variables.options
                );
                expect(
                    queryExecute(
                        "SELECT COUNT(*) AS total FROM cbq_jobs WHERE queue='custom-notifications'",
                        {},
                        { "datasource": "megaphone" }
                    ).total[ 1 ]
                ).toBe( 1 );
            } );
            it( "allows a custom adapter or explicit polling without cbq jobs", () => {
                var adapter = new tests.resources.DurableQueueFixture();
                variables.settings.durable.queueAdapter = adapter;
                variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    {},
                    variables.options
                );
                expect( adapter.getDeliveries().len() ).toBe( 1 );
                expect( jobs().recordCount ).toBe( 0 );
                variables.settings.durable.queueAdapter = "";
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
                expect( deserializeJob( jobs().payload[ 1 ] ).handle() ).toBe( "retryable" );
                var rows = jobs();
                expect( rows.recordCount ).toBe( 2 );
                expect( provider.getSendCount() ).toBe( 1 );
                expect( rows.availableDate[ 2 ] - rows.createdDate[ 2 ] ).toBeGTE( 28 );
                expect(
                    variables.deliveries.getDelivery( publication.getDeliveries()[ 1 ].getId() ).getTransportCount()
                ).toBe( 1 );
            } );
            it( "defines a default worker when durable resolution is configured", () => {
                var config = getWireBox().getInstance( "CBQConfig@megaphone" );
                config.configure();
                expect( config.getWorkerPoolDefinitions().keyExists( "megaphone" ) ).toBeTrue();
            } );
            it( "reschedules deferred policy checks without consuming a transport", () => {
                var publication = variables.service.queue(
                    variables.owner,
                    "QueueNotification",
                    {},
                    variables.options
                );
                variables.policy.setStatus( "deferred" );
                expect( deserializeJob( jobs().payload[ 1 ] ).handle() ).toBe( "retryable" );
                expect( jobs().recordCount ).toBe( 2 );
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
                expect( deserializeJob( jobs().payload[ 1 ] ).handle() ).toBe( "busy" );
                var rows = jobs();
                expect( rows.recordCount ).toBe( 2 );
                expect( rows.availableDate[ 2 ] - rows.createdDate[ 2 ] ).toBeGTE( 118 );
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
            .getConnection( variables.settings.durable.queueConnection )
            .getProvider()
            .deserializeJob( arguments.payload, 1 );
    }
    private any function outcomeProvider( required string status ) {
        variables.service.registerChannels( { "database": { "provider": "QueueOutcomeProvider", "properties": {} } } );
        var provider = variables.service.getChannel( "database" );
        provider.setOutcome( arguments.status );
        return provider;
    }

}
