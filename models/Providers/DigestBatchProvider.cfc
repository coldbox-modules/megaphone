/** Publishes a normal notification, leaving its delivery channels to the application. */
component extends="BaseProvider" {

    property name="digests" inject="EmailDigestService@megaphone";
    property name="log" inject="logbox:logger:{this}";

    public string function getProviderName() {
        return "DigestBatchProvider";
    }

    public DeliveryPreparation function prepareDelivery(
        required any notifiable,
        required any notification,
        required any delivery
    ) {
        var batchId = arguments.notification.getQueueProperties().batchId;
        var ready = variables.digests.prepareBatch( arguments.notifiable, batchId );
        if ( ready.status != "ready" ) {
            return newDeliveryPreparation().configure( { "status": "suppressed", "reason": ready.reason } );
        }
        return newDeliveryPreparation().configure( { "data": { "notifiable": arguments.notifiable, "batchId": batchId } } );
    }

    public DeliveryResult function sendDelivery( required any prepared, required any delivery ) {
        var data = arguments.prepared.getData();
        try {
            var publication = variables.digests.publishBatch( data.notifiable, data.batchId );
        } catch ( any error ) {
            // A rolled-back local publication has no uncertain external transport outcome.
            variables.log.error( "Digest summary publication failed for batch [#data.batchId#].", error );
            return newDeliveryResult().configure( { "status": "retryable", "reason": "digest-publication-error" } );
        }
        // Publication commits before any external transport. Scheduler polling also recovers interrupted dispatch.
        try {
            variables.digests.dispatchPublishedBatch( data.batchId );
        } catch ( any error ) {
            variables.log.error(
                "Digest summary was published; channel dispatch will be recovered by polling for batch [#data.batchId#].",
                error
            );
        }
        return newDeliveryResult().configure( { "status": "accepted", "reason": publication.status == "suppressed" ? "digest-suppressed" : "" } );
    }

    private any function newDeliveryPreparation() provider="DeliveryPreparation@megaphone" {
    }

    private any function newDeliveryResult() provider="DeliveryResult@megaphone" {
    }

}
