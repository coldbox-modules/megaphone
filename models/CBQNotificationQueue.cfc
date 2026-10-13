/** cbq carries delivery references; Megaphone owns transport attempts and outcomes. */
component singleton {

    property name="settings" inject="coldbox:moduleSettings:megaphone";
    property name="wirebox" inject="wirebox";

    public void function enqueue( required NotificationDelivery delivery ) {
        if ( !listFind( "queued,retryable,processing", arguments.delivery.getState() ) ) {
            return;
        }
        var availableDate = arguments.delivery.getAvailableDate();
        if ( arguments.delivery.getState() == "processing" ) {
            availableDate = arguments.delivery.getLeaseUntil();
        }
        variables.wirebox
            .getInstance( "NotificationDeliveryJob@megaphone" )
            .setProperties( { "deliveryId": arguments.delivery.getId() } )
            .setMaxAttempts( 1 )
            .setTimeout( variables.settings.durable.queueTimeout )
            .onConnection( variables.settings.durable.queueConnection )
            .onQueue( variables.settings.durable.queueName )
            .setDelay( max( 0, dateDiff( "s", now(), availableDate ) ) )
            .dispatch();
    }

}
