/** Existing store adapters need only their original batch method. */
component accessors="true" {

    property name="store";
    property name="batchCounter";
    public array function enqueueMany( required array intents ) {
        variables.batchCounter.count++;
        return variables.store.enqueueMany( arguments.intents );
    }

}
