/** A single cbq attempt; only a known safe Megaphone outcome can schedule another job. */
component extends="cbq.models.Jobs.AbstractJob" {

    property name="deliveries" inject="NotificationDeliveryService@megaphone";
    property name="runtime" inject="NotificationRuntime@megaphone";

    public string function handle() {
        var id = getProperties().deliveryId;
        var outcome = variables.deliveries.dispatch( id );
        if ( listFind( "retryable,deferred,busy", outcome.getStatus() ) ) {
            var work = variables.deliveries.getDelivery( id );
            var queue = variables.runtime.resolve( "queueAdapter" );
            if ( !isNull( work ) && !isNull( queue ) ) {
                queue.enqueue( work );
            }
        }
        return outcome.getStatus();
    }

}
