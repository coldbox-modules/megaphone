/** A custom public override must remain the fallback admission boundary. */
component extends="megaphone.models.Storage.DeliveryStore" accessors="true" {

    property name="batchCounter";
    public array function enqueueMany( required array intents ) {
        variables.batchCounter.count++;
        return super.enqueueMany( argumentCollection = arguments );
    }

}
