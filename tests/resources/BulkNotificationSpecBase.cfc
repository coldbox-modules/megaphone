/** Shared real database setup for public bulk admission API regressions. */
component extends="tests.specs.integration.DeliveryStoreSpec" {

    function beforeAll() {
        super.beforeAll();
        var binder = variables.injector.getBinder();
        variables.config = { "queue": { "queueAdapter": "", "snapshotHasher": "" } };
        binder
            .map( "NotificationRuntime@megaphone" )
            .to( "megaphone.models.Delivery.NotificationRuntime" )
            .property( name = "settings", value = variables.config )
            .property( name = "wirebox", value = variables.injector );
        binder
            .map( "NotificationSnapshotHasher@megaphone" )
            .to( "megaphone.models.Delivery.NotificationSnapshotHasher" );
        binder.map( "NotificationPlan@megaphone" ).to( "megaphone.models.Delivery.NotificationPlan" );
        binder.map( "NotificationPublication@megaphone" ).to( "megaphone.models.Delivery.NotificationPublication" );
        binder.map( "PreferenceResolver@megaphone" ).to( "megaphone.models.Preferences.PreferenceResolver" );
        binder.map( "PreferenceStore@megaphone" ).to( "megaphone.models.Storage.PreferenceStore" );
        binder
            .map( "NotificationPreferenceService@megaphone" )
            .to( "megaphone.models.Preferences.NotificationPreferenceService" );
        variables.service = variables.injector.getInstance( "NotificationService@megaphone" );
        var channel = variables.injector.getInstance( "DatabaseProvider@megaphone" );
        variables.service.setChannels( { "database": channel, "email": channel, "push": channel } );
        variables.preferenceService = variables.injector.getInstance( "NotificationPreferenceService@megaphone" );
    }
    public struct function notificationRequest( required string key, string message = "bulk" ) {
        return {
            "notifiables": variables.owner,
            "notification": new tests.resources.QueueNotification(),
            "properties": {
                "message": arguments.message,
                "channelNames": [ "database", "email", "push" ],
                "choices": { "push": false }
            },
            "options": {
                "namespace": "bulk-test",
                "eventKey": arguments.key,
                "version": 1,
                "occurredAt": createDateTime( 2026, 10, 15, 12, 0, 0 ),
                "availableDate": createDateTime( 2026, 10, 15, 12, 0, 0 )
            }
        };
    }

}
