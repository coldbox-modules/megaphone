component {

    /**
     * The event type for the metadata payload.
     */
    property name="type" type="string";

    /**
     * The metadata payload.
     */
    property name="payload" type="struct";

    public EventMetadata function init( required string type, struct payload = {} ) {
        variables.type = arguments.type;
        variables.payload = arguments.payload;
        return this;
    }

    public struct function getMemento() {
        return { "event_type": variables.type, "event_payload": variables.payload };
    }

}
