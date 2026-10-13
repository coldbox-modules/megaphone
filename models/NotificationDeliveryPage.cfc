component accessors="true" {

    property name="results" setter="false";
    property name="hasMore" setter="false";
    /**
     * Captures a delivery page and whether more results are available.
     * @returns NotificationDeliveryPage
     */
    public NotificationDeliveryPage function init( required array results, required boolean hasMore ) {
        variables.results = arguments.results;
        variables.hasMore = arguments.hasMore;
        return this;
    }
    /**
     * Returns this object's public data as a serializable memento.
     * @returns struct
     */
    public struct function getMemento() {
        return {
            "results": variables.results.map( ( delivery ) => delivery.getMemento() ),
            "hasMore": variables.hasMore
        };
    }

}
