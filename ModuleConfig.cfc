component {

    this.name = "megaphone";
    this.author = "Ortus Solutions";
    this.webUrl = "https://github.com/coldbox-modules/megaphone";
    this.dependencies = [ "qb", "str" ];
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
            "queue": {
                "queueAdapter": "CBQNotificationQueue@megaphone",
                "defaultConnection": "",
                "defaultQueue": "",
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
        param settings.queue = {};
        param settings.queue.queueAdapter = "CBQNotificationQueue@megaphone";
        param settings.queue.defaultConnection = "";
        param settings.queue.defaultQueue = "";
        param settings.queue.leaseSeconds = 60;
        param settings.queue.maxAttempts = 5;
        param settings.queue.retrySeconds = 30;
        param settings.queue.maxRecoveryAttempts = 5;
        param settings.queue.maxRecoveryAllowance = 45;
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
                properties.maxRecoveryAttempts = settings.queue.maxRecoveryAttempts;
                properties.maxRecoveryAllowance = settings.queue.maxRecoveryAllowance;
            }
            binder
                .map( stores[ key ] & "@megaphone" )
                .to( moduleMapping & ".models.Storage." & stores[ key ] )
                .initArg( name = "properties", value = properties );
        }
        variables.wirebox.getInstance( "NotificationService@megaphone" ).registerChannels( settings.channels ?: {} );
    }

}
