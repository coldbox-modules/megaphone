/** Fallback for applications without a cbq config; never replaces application connections. */
component extends="cbq.models.BaseConfig" {

    property name="settings" inject="coldbox:moduleSettings:megaphone";
    property name="deliveries" inject="DeliveryStore@megaphone";

    public void function configure() {
        var policy = variables.settings.durable;
        newConnection( policy.queueConnection )
            .setProvider( "DBProvider@cbq" )
            .setProperties( { "queryOptions": variables.deliveries.getQueryOptions() } );
        // Synchronous-only applications do not start durable workers or need queue tables.
        if (
            isSimpleValue( policy.queueAdapter ) && policy.queueAdapter == "CBQNotificationQueue@megaphone" && (
                !isSimpleValue( policy.notifiableResolver ?: "" ) || len( policy.notifiableResolver ?: "" )
            )
        ) {
            newWorkerPool( "megaphone" )
                .forConnection( policy.queueConnection )
                .onQueue( policy.queueName )
                .quantity( 1 )
                .timeout( policy.queueTimeout )
                .maxAttempts( 1 );
        }
    }

}
