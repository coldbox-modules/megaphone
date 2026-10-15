/** A custom public override must remain the fallback admission boundary. */
component extends="megaphone.models.Storage.EventStore" accessors="true" {

    property name="batchCounter";
    public array function recordMany( required array events ) {
        variables.batchCounter.count++;
        return super.recordMany( argumentCollection = arguments );
    }

}
