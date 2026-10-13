/** cbq handles release timing; Megaphone alone authorizes another transport. */
component extends="cbq.models.Jobs.AbstractJob" {

    property name="deliveries" inject="NotificationDeliveryService@megaphone";

    /**
     * Dispatches the stored delivery ID and releases only outcomes safe to retry through cbq.
     * @returns string
     */
    public string function handle() {
        // A reused synchronous job must clear its prior release decision.
        setIsReleased( false );
        setMaxAttempts( max( 1, getCurrentAttempt() ) );
        var id = getProperties().deliveryId;
        var outcome = variables.deliveries.dispatch( id );
        if ( listFind( "retryable,deferred,busy", outcome.getStatus() ) ) {
            var work = variables.deliveries.getDelivery( id );
            if ( !isNull( work ) && listFind( "queued,retryable,processing", work.getState() ) ) {
                var availableDate = work.getState() == "processing" ? work.getLeaseUntil() : work.getAvailableDate();
                // Allow exactly one provider-managed retry after this known safe result.
                setMaxAttempts( getCurrentAttempt() + 1 );
                release( max( 1, dateDiff( "s", now(), availableDate ) ) );
            }
        }
        return outcome.getStatus();
    }

}
