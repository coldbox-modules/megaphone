component accessors="true" {

    property name="results" setter="false";
    property name="hasMore" setter="false";
    /**
     * Captures a page of recovery receipts and whether more results are available.
     * @returns NotificationRecoveryPage
     */
    public NotificationRecoveryPage function init( array results = [], boolean hasMore = false ) {
        return configure( argumentCollection = arguments );
    }

    /**
     * Configures the NotificationRecoveryPage after WireBox constructs and injects it.
     * @returns NotificationRecoveryPage
     */
    public NotificationRecoveryPage function configure( required array results, required boolean hasMore ) {
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
