/** cbq carries delivery references; Megaphone owns transport attempts and outcomes. */
component singleton {

    property name="settings" inject="coldbox:moduleSettings:megaphone";
    property name="wirebox" inject="wirebox";

    public void function enqueue( required NotificationDelivery delivery, string connection, string queue ) {
        if ( !listFind( "queued,retryable,processing", arguments.delivery.getState() ) ) {
            return;
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
        }
        if ( !isNull( arguments.connection ) ) {
            job.onConnection( arguments.connection );
        } else if ( len( variables.settings.durable.queueConnection ) ) {
            job.onConnection( variables.settings.durable.queueConnection );
        }
        job.dispatch();
    }

}
