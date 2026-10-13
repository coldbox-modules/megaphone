component {

    this.name = "megaphone";
    this.author = "Ortus Solutions";
    this.webUrl = "https://github.com/coldbox-modules/megaphone";
    this.dependencies = [ "qb", "str", "cbq" ];
    this.cfmapping = "megaphone";

    function configure() {
        settings = {
            "channels": {},
            "storage": {
                "events": {},
                "deliveries": {},
                "preferences": {},
                "subscriptions": {}
            },
            "durable": {
                "queueAdapter": "CBQNotificationQueue@megaphone",
                "queueConnection": "",
                "notifiableResolver": "",
                "eligibilityPolicy": "",
                "snapshotHasher": "",
                "deliveryPolicy": "",
                "leaseSeconds": 60,
                "maxAttempts": 5,
                "retrySeconds": 30,
                "maxRecoveryAttempts": 5,
                "maxRecoveryAllowance": 45
            }
        };

        binder.getInjector().registerDSL( "megaphone", "#moduleMapping#.dsl.MegaphoneDSL" );
    }

    function onLoad() {
        param settings.storage = {};
        param settings.durable = {};
        param settings.durable.queueAdapter = "CBQNotificationQueue@megaphone";
        param settings.durable.queueConnection = "";
        param settings.durable.leaseSeconds = 60;
        param settings.durable.maxAttempts = 5;
        param settings.durable.retrySeconds = 30;
        param settings.durable.maxRecoveryAttempts = 5;
        param settings.durable.maxRecoveryAllowance = 45;
        var stores = {
            "events": "EventStore",
            "deliveries": "DeliveryStore",
            "preferences": "PreferenceStore",
            "subscriptions": "SubscriptionStore"
        };
        for ( var key in stores ) {
            var properties = settings.storage[ key ] ?: {};
            settings.storage[ key ] = properties;
            if ( key == "deliveries" ) {
                properties = duplicate( properties );
                properties.maxRecoveryAttempts = settings.durable.maxRecoveryAttempts;
                properties.maxRecoveryAllowance = settings.durable.maxRecoveryAllowance;
            }
            binder
                .map( stores[ key ] & "@megaphone" )
                .to( moduleMapping & ".models." & stores[ key ] )
                .initArg( name = "properties", value = properties );
        }
        variables.wirebox.getInstance( "NotificationService@megaphone" ).registerChannels( settings.channels ?: {} );
        configureDefaultQueue();
    }

    private void function configureDefaultQueue() {
        var cbqSettings = variables.controller.getSetting( "moduleSettings" ).cbq;
        // Existing application cbq configurations take precedence over the bundled one.
        if ( cbqSettings.configPath == "config.cbq" && !variables.wirebox.containsInstance( cbqSettings.configPath ) ) {
            cbqSettings.configPath = "#moduleMapping#.models.CBQConfig";
        }
    }

}
