component extends="tests.resources.ModuleIntegrationSpec" {

    function run() {
        describe( "Digest module registration", () => {
            it( "resolves the generic lifecycle service through both public service names", () => {
                var generic = getInstance( "DigestService@megaphone" );
                var legacy = getInstance( "EmailDigestService@megaphone" );
                expect( listLast( getMetadata( generic ).name, "." ) ).toBe( "DigestService" );
                expect( generic ).toBe( legacy );
                expect( getInstance( "NotificationService@megaphone" ).getChannel( "digestBatch" ).getProviderName() ).toBe( "DigestBatchProvider" );
            } );
            it( "resolves configured named definitions and automatically registers the batch provider", () => {
                var digests = getInstance( "EmailDigestService@megaphone" );
                var configuredStore = prepareMock( digests ).$getProperty( "store", "variables" );
                expect( configuredStore.getQueryOptions().datasource ).toBe( "megaphone" );
                expect( configuredStore.getQueryOptions().timeout ).toBe( 17 );
                expect( digests.getDefinition( "moduleSmoke" ).name ).toBe( "moduleSmoke" );
                expect(
                    getInstance( "NotificationService@megaphone" ).getChannel( "emailDigestBatch" ).getProviderName()
                ).toBe( "EmailDigestBatchProvider" );
            } );
            it( "adds a new digest and subscription timezone task to the running module scheduler", () => {
                var scheduler = getInstance( "cbScheduler@megaphone" );
                var digests = getInstance( "EmailDigestService@megaphone" );
                var config = getController().getSetting( "modules" ).megaphone.settings;
                var name = "runtime" & replace( createUUID(), "-", "", "all" );
                var before = scheduler.getRegisteredTasks();
                try {
                    expect( scheduler.hasStarted() ).toBeTrue();
                    digests.registerDigest(
                        name,
                        {
                            "schedule": ( task ) => task
                                .setTimezone( "Europe/London" )
                                .everyDayAt( "23:59" )
                                .when( () => false ),
                            "emailChannel": "email",
                            "policy": "tests.resources.DigestPolicyFixture",
                            "renderer": "tests.resources.DigestRendererFixture"
                        }
                    );
                    expect( scheduler.getRegisteredTasks().len() ).toBe( before.len() + 1 );
                    digests.setSubscription(
                        new tests.resources.InboxRecipient(),
                        name,
                        "digest",
                        "America/Denver"
                    );
                    expect( scheduler.getRegisteredTasks().len() ).toBe( before.len() + 2 );
                    var zones = [];
                    for ( var taskName in scheduler.getRegisteredTasks() ) {
                        if ( !before.find( taskName ) ) {
                            var record = scheduler.getTaskRecord( taskName );
                            zones.append( record.task.getTimezone().getId() );
                            expect( record.task.getScheduled() ).toBeTrue();
                            expect( isObject( record.future ) ).toBeTrue();
                            expect( record.task.isConstrained() ).toBeTrue();
                        }
                    }
                    expect( zones.sort( "text" ) ).toBe( [ "America/Denver", "Europe/London" ] );
                } finally {
                    removeRegisteredTasks( scheduler, before );
                    structDelete( config.digests, name );
                }
            } );
            it( "registers notification-based definitions on the existing module scheduler", () => {
                var scheduler = getInstance( "cbScheduler@megaphone" );
                var digests = getInstance( "DigestService@megaphone" );
                var config = getController().getSetting( "modules" ).megaphone.settings;
                var name = "generic" & replace( createUUID(), "-", "", "all" );
                var before = scheduler.getRegisteredTasks();
                try {
                    digests.registerDigest(
                        name,
                        {
                            "timezone": "UTC",
                            "schedule": ( task ) => task.everyDayAt( "23:59" ).when( () => false ),
                            "notification": "tests.resources.GenericDigestSummaryFixture",
                            "policy": "tests.resources.GenericDigestPolicyFixture"
                        }
                    );
                    digests.addSubscription(
                        notifiable = new tests.resources.InboxRecipient(),
                        digestName = name,
                        timezone = "America/Denver"
                    );
                    expect( scheduler.getRegisteredTasks().len() ).toBe( before.len() + 2 );
                } finally {
                    removeRegisteredTasks( scheduler, before );
                    structDelete( config.digests, name );
                }
            } );
            it( "does not query delivery storage when no digests are configured", () => {
                var scheduler = getInstance( "cbScheduler@megaphone" );
                var task = scheduler.getTaskRecord( "emailDigest-deliveries" ).task;
                var config = getController().getSetting( "modules" ).megaphone.settings;
                var definitions = config.digests;
                var properties = prepareMock( getInstance( "EmailDigestService@megaphone" ) )
                    .$getProperty( "deliveryStore", "variables" )
                    .getProperties();
                var datasource = properties.datasource;
                var failures = task.getStats().totalFailures;
                try {
                    config.digests = {};
                    properties.datasource = "digestStorageMustNotBeQueried";
                    task.run( force = true );
                    expect( task.getStats().totalFailures ).toBe( failures );
                } finally {
                    config.digests = definitions;
                    properties.datasource = datasource;
                }
            } );
            it( "registers immediate-only definitions without adding calendar tasks", () => {
                var scheduler = getInstance( "cbScheduler@megaphone" );
                var digests = getInstance( "EmailDigestService@megaphone" );
                var config = getController().getSetting( "modules" ).megaphone.settings;
                var name = "instant" & replace( createUUID(), "-", "", "all" );
                var count = scheduler.getRegisteredTasks().len();
                try {
                    digests.registerDigest(
                        name,
                        {
                            "emailChannel": "email",
                            "policy": "tests.resources.DigestPolicyFixture",
                            "renderer": "tests.resources.DigestRendererFixture"
                        }
                    );
                    digests.setSubscription( new tests.resources.InboxRecipient(), name, "immediate" );
                    expect( scheduler.getRegisteredTasks().len() ).toBe( count );
                } finally {
                    structDelete( config.digests, name );
                }
            } );
            it( "freezes and dispatches a native scheduler occurrence through simulated receipts", () => {
                var scheduler = getInstance( "cbScheduler@megaphone" );
                var digests = getInstance( "EmailDigestService@megaphone" );
                var notifications = getInstance( "NotificationService@megaphone" );
                var config = getController().getSetting( "modules" ).megaphone.settings;
                var name = "scheduled" & replace( createUUID(), "-", "", "all" );
                var before = scheduler.getRegisteredTasks();
                var mail = new tests.resources.DigestMailProviderFixture();
                notifications.getChannels()[ name ] = mail;
                try {
                    digests.registerDigest(
                        name,
                        {
                            "schedule": "everyDayAt 23:59",
                            "timezone": "UTC",
                            "emailChannel": name,
                            "policy": new tests.resources.DigestPolicyFixture(),
                            "renderer": new tests.resources.DigestRendererFixture()
                        }
                    );
                    var recipient = new tests.resources.InboxRecipient();
                    digests.setSubscription(
                        notifiable = recipient,
                        digestName = name,
                        mode = "digest",
                        clock = dateAdd( "n", -1, now() )
                    );
                    digests.collect(
                        recipient,
                        name,
                        "scheduled-item",
                        {},
                        digests.occurredAt( now() )
                    );
                    var taskName = scheduler.getRegisteredTasks().filter( ( registered ) => !before.find( registered ) )[
                        1
                    ];
                    scheduler.getTaskRecord( taskName ).task.run( force = true );
                    expect( mail.getSent().len() ).toBe( 1 );
                    expect( mail.getSent()[ 1 ].keys ).toBe( [ "scheduled-item" ] );
                    scheduler.getTaskRecord( taskName ).task.run( force = true );
                    expect( mail.getSent().len() ).toBe( 1 );
                } finally {
                    removeRegisteredTasks( scheduler, before );
                    structDelete( config.digests, name );
                    structDelete( notifications.getChannels(), name );
                }
            } );
            it( "collects and freezes using activated WireBox services without a mail send", () => {
                var recipient = new tests.resources.InboxRecipient();
                var digests = getInstance( "EmailDigestService@megaphone" );
                var subscription = digests.setSubscription(
                    notifiable = recipient,
                    digestName = "moduleSmoke",
                    mode = "digest"
                );
                var instant = getInstance( "EmailDigestSchedule@megaphone" ).epoch();
                getInstance( "NotificationService@megaphone" ).notify(
                    recipient,
                    new tests.resources.DigestNotificationFixture(),
                    {
                        "digestName": "moduleSmoke",
                        "itemKey": createUUID(),
                        "data": { "message": "test" },
                        "occurredAt": instant
                    }
                );
                var batches = digests.prepareDigest( "moduleSmoke", instant + 60000, subscription.timezone );
                expect( batches.len() ).toBe( 1 );
                expect( batches[ 1 ].state ).toBe( "frozen" );
                expect(
                    getInstance( "NotificationDeliveryService@megaphone" ).getAttempts( batches[ 1 ].deliveryId ).len()
                ).toBe( 0 );
            } );
        } );
    }

    private void function removeRegisteredTasks( required any scheduler, required array before ) {
        for ( var taskName in arguments.scheduler.getRegisteredTasks() ) {
            if ( !arguments.before.find( taskName ) ) {
                arguments.scheduler.removeTask( taskName );
            }
        }
    }

}
