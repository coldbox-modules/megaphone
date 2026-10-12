component accessors="true" {

    property name="event" setter="false";
    property name="deliveries" setter="false";

    public NotificationPublication function init( required NotificationEvent event, array deliveries = [] ) {
        variables.event = arguments.event;
        variables.deliveries = arguments.deliveries;
        return this;
    }

    public struct function getMemento() {
        return {
            "event": variables.event.getMemento(),
            "deliveries": variables.deliveries.map( ( delivery ) => delivery.getMemento() )
        };
    }

}
