/** A configured mapping may transform captured snapshots before they are hashed. */
component extends="megaphone.models.Delivery.NotificationPlan" {

    public any function configure(
        struct event = {},
        array deliveries = [],
        any admitAfter,
        struct queueOptions = {}
    ) {
        if ( structKeyExists( arguments.event, "payload" ) ) {
            arguments.event.payload.mappingMarker = "custom-plan";
            for ( var intent in arguments.deliveries ) {
                intent.routingData.mappingMarker = "custom-plan";
            }
        }
        return super.configure( argumentCollection = arguments );
    }

}
