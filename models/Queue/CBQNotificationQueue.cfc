/** cbq carries delivery references; Megaphone owns transport attempts and outcomes. */
component singleton implements="megaphone.models.Interfaces.INotificationQueue" {

    property name="settings" inject="box:moduleSettings:megaphone";
    property name="wirebox" inject="wirebox";
    property name="moduleService" inject="box:moduleService";

    /**
     * Enqueues a delivery-ID job on the selected registered cbq connection and queue.
     */
    public void function enqueue(
        required megaphone.models.Delivery.NotificationDelivery delivery,
        string connection,
        string queue
    ) {
        if ( !listFind( "queued,retryable,processing", arguments.delivery.getState() ) ) {
            return;
        }
        if ( !variables.moduleService.isModuleRegistered( "cbq" ) ) {
            throw(
                type = "Megaphone.Queue.MissingCBQ",
                message = "Install and configure cbq to queue notifications with Megaphone's cbq adapter."
            );
        }
        variables.moduleService.activateModule( "cbq" );
        if ( !variables.moduleService.isModuleActive( "cbq" ) ) {
            throw(
                type = "Megaphone.Queue.MissingCBQ",
                message = "The cbq module must be active to queue notifications with Megaphone's cbq adapter."
            );
        }
        var availableDate = arguments.delivery.getAvailableDate();
        if ( arguments.delivery.getState() == "processing" ) {
            availableDate = arguments.delivery.getLeaseUntil();
        }
        var job = variables.wirebox
            .getInstance( "NotificationDeliveryJob@megaphone" )
            .setProperties( { "deliveryId": arguments.delivery.getId() } )
            .setMaxAttempts( 1 )
            .setDelay( max( 0, dateDiff( "s", now(), availableDate ) ) );
        if ( !isNull( arguments.queue ) ) {
            job.onQueue( arguments.queue );
        } else if ( len( variables.settings.queue.defaultQueue ) ) {
            job.onQueue( variables.settings.queue.defaultQueue );
        }
        if ( !isNull( arguments.connection ) ) {
            job.onConnection( arguments.connection );
        } else if ( len( variables.settings.queue.defaultConnection ) ) {
            job.onConnection( variables.settings.queue.defaultConnection );
        }
        job.dispatch();
    }

}
