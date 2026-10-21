/** Existing store adapters need only their original batch method. */
component accessors="true" {

    property name="store";
    property name="batchCounter";
    public array function recordMany( required array events ) {
        variables.batchCounter.count++;
        return variables.store.recordMany( arguments.events );
    }

}
