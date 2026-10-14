component accessors="true" {

    property name="event" setter="false";
    property name="deliveries" setter="false";
    property name="collections" setter="false";

    /**
     * Captures the persisted event, delivery objects, and collection admissions returned by publication.
     * @returns NotificationPublication
     */
    public NotificationPublication function init(
        NotificationEvent event,
        array deliveries = [],
        array collections = []
    ) {
        variables.collections = arguments.collections;
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
    public NotificationPublication function configure(
        required NotificationEvent event,
        array deliveries = [],
        array collections = []
    ) {
        variables.event = arguments.event;
        variables.deliveries = arguments.deliveries;
        variables.collections = arguments.collections;
        return this;
    }

    /**
     * Returns the saved event, delivery mementos, and separate collection admissions.
     * @returns struct
     */
    public struct function getMemento() {
        return {
            "event": variables.event.getMemento(),
            "deliveries": variables.deliveries.map( ( delivery ) => delivery.getMemento() ),
            "collections": duplicate( variables.collections )
        };
    }

}
