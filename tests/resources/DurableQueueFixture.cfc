component accessors="true" implements="megaphone.models.Interfaces.INotificationQueue" {

    property name="fail";
    property name="deliveries";
    /** Captures queued deliveries and optionally simulates a queue insertion failure. */
    public DurableQueueFixture function init( boolean fail = false ) {
        variables.fail = arguments.fail;
        variables.deliveries = [];
        return this;
    }
    /** Implements the same typed queue contract as an application adapter. */
    public void function enqueue(
        required megaphone.models.Delivery.NotificationDelivery delivery,
        string connection,
        string queue
    ) {
        variables.deliveries.append( arguments.delivery.getMemento() );
        if ( variables.fail ) {
            throw( type = "QueueFixtureUnavailable", message = "Queue adapter failed before commit." );
        }
    }

}
