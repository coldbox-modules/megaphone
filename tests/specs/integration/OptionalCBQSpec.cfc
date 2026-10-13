/** Run this bundle with cbq absent; the normal suite covers installed cbq. */
component extends="tests.resources.ModuleIntegrationSpec" {

    function beforeAll() {
        super.beforeAll();
        variables.cbqAvailable = getController().getModuleService().isModuleRegistered( "cbq" );
        if ( variables.cbqAvailable ) {
            return;
        }
        var binder = getWireBox().getBinder();
        binder.map( "QueueNotification" ).to( "tests.resources.QueueNotification" );
        binder
            .map( "QueueNotifiableResolver" )
            .to( "tests.resources.QueueNotifiableResolver" )
            .asSingleton();
        variables.settings = getController().getSetting( "moduleSettings" ).megaphone;
        variables.service = getWireBox().getInstance( "NotificationService@megaphone" );
        variables.deliveries = getWireBox().getInstance( "NotificationDeliveryService@megaphone" );
        variables.resolver = getWireBox().getInstance( "QueueNotifiableResolver" );
    }

    function run() {
        describe(
            "Megaphone without cbq",
            () => {
                beforeEach( () => {
                    variables.savedSettings = duplicate( variables.settings.queue );
                    variables.settings.queue.queueAdapter = "CBQNotificationQueue@megaphone";
                    variables.settings.queue.notifiableResolver = "QueueNotifiableResolver";
                    variables.owner = new tests.resources.InboxRecipient();
                    variables.resolver.register( variables.owner );
                    variables.service.registerChannels( { "database": { "provider": "DatabaseProvider@megaphone", "properties": {} } } );
                } );
                afterEach( () => {
                    variables.settings.queue = variables.savedSettings;
                } );
                it( "activates Megaphone and sends synchronous notifications without cbq", () => {
                    expect( getController().getModuleService().isModuleActive( "megaphone" ) ).toBeTrue();
                    expect( getController().getModuleService().isModuleRegistered( "cbq" ) ).toBeFalse();
                    var notification = variables.service.notify(
                        variables.owner,
                        "QueueNotification",
                        { "message": "synchronous" }
                    );
                    expect( notification ).toBeInstanceOf( "megaphone.models.BaseNotification" );
                    var inbox = getWireBox()
                        .getInstance( "DatabaseNotificationService@megaphone" )
                        .getNotifications( variables.owner );
                    expect( inbox.getResults().len() ).toBe( 1 );
                    expect( inbox.getResults()[ 1 ].getData().message ).toBe( "synchronous" );
                } );
                it( "plans without cbq and rolls back publication with a Megaphone exception when queueing", () => {
                    var plan = variables.service.plan( variables.owner, "QueueNotification" );
                    expect( plan.getDeliveries().len() ).toBe( 1 );
                    expect( () => variables.service.queuePlan( plan ) ).toThrow( "Megaphone.Queue.MissingCBQ" );
                    expect( variables.deliveries.getDueDeliveries() ).toBeEmpty();
                    expect(
                        queryExecute(
                            "SELECT COUNT(*) AS total FROM megaphone_events",
                            {},
                            { "datasource": "megaphone" }
                        ).total[ 1 ]
                    ).toBe( 0 );
                } );
                it( "queues through a custom adapter and dispatches without cbq", () => {
                    var adapter = new tests.resources.DurableQueueFixture();
                    variables.settings.queue.queueAdapter = adapter;
                    var publication = variables.service.queue( variables.owner, "QueueNotification" );
                    expect( adapter.getDeliveries().len() ).toBe( 1 );
                    expect( variables.deliveries.dispatch( publication.getDeliveries()[ 1 ].getId() ).getStatus() ).toBe( "accepted" );
                } );
                it( "supports polling without cbq or a queue adapter", () => {
                    variables.settings.queue.queueAdapter = "";
                    var publication = variables.service.queue( variables.owner, "QueueNotification" );
                    expect( variables.deliveries.getDueDeliveries().len() ).toBe( 1 );
                    expect( variables.deliveries.dispatch( publication.getDeliveries()[ 1 ].getId() ).getStatus() ).toBe( "accepted" );
                } );
            },
            [],
            false,
            directoryExists( expandPath( "/megaphone/modules/cbq" ) )
        );
    }

}
