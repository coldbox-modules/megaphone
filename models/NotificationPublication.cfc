component accessors="true" {

    property name="event" setter="false";
    property name="deliveries" setter="false";

    /**
     * Captures the persisted event and delivery objects returned by queueing.
     * @returns NotificationPublication
     */
    public NotificationPublication function init( NotificationEvent event, array deliveries = [] ) {
        if ( isNull( arguments.event ) ) {
            variables.deliveries = [];
            return this;
        }
        return configure( argumentCollection = arguments );
    }

    /**
     * Configures the NotificationPublication after WireBox constructs and injects it.
     * @returns NotificationPublication
     */
    public NotificationPublication function configure( required NotificationEvent event, array deliveries = [] ) {
        variables.event = arguments.event;
        variables.deliveries = arguments.deliveries;
        return this;
    }

    /**
     * Returns the saved event and its deliveries as mementos.
     * @returns struct
     */
    public struct function getMemento() {
        return {
            "event": variables.event.getMemento(),
            "deliveries": variables.deliveries.map( ( delivery ) => delivery.getMemento() )
        };
    }

}
