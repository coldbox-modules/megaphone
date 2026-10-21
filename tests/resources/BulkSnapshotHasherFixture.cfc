component accessors="true" {

    property name="calls" default="0";
    public string function digest( required struct value, required struct context ) {
        return "custom-" & new megaphone.models.Delivery.NotificationSnapshotHasher().digest(
            arguments.value,
            arguments.context
        );
    }
    public array function digestMany( required array entries ) {
        variables.calls++;
        return arguments.entries.map( ( entry ) => digest( entry.value, entry.context ) );
    }

}
