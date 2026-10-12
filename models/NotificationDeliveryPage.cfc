component accessors="true" {

    property name="results" setter="false";
    property name="hasMore" setter="false";
    public NotificationDeliveryPage function init( required array results, required boolean hasMore ) {
        variables.results = arguments.results;
        variables.hasMore = arguments.hasMore;
        return this;
    }
    public struct function getMemento() {
        return {
            "results": variables.results.map( ( delivery ) => delivery.getMemento() ),
            "hasMore": variables.hasMore
        };
    }

}
