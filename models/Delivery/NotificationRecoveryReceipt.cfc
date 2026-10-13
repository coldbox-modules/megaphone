component accessors="true" {

    property name="id" setter="false";
    property name="deliveryId" setter="false";
    property name="requestKey" setter="false";
    property name="intentHash" setter="false";
    property name="actorId" setter="false";
    property name="actorLabel" setter="false";
    property name="priorState" setter="false";
    property name="priorAttemptCount" setter="false";
    property name="priorTransportCount" setter="false";
    property name="priorReason" setter="false";
    property name="priorProviderReference" setter="false";
    property name="additionalAttempts" setter="false";
    property name="createdDate" setter="false";
    /**
     * Copies persisted recovery receipt fields into the public receipt object.
     * @returns NotificationRecoveryReceipt
     */
    public NotificationRecoveryReceipt function init( struct data = {} ) {
        return configure( argumentCollection = arguments );
    }

    /**
     * Configures the NotificationRecoveryReceipt after WireBox constructs and injects it.
     * @returns NotificationRecoveryReceipt
     */
    public NotificationRecoveryReceipt function configure( required struct data ) {
        for (
            var key in listToArray( "id,deliveryId,requestKey,intentHash,actorId,actorLabel,priorState,priorAttemptCount,priorTransportCount,priorReason,priorProviderReference,additionalAttempts,createdDate" )
        ) {
            if ( !isNull( arguments.data[ key ] ) ) {
                variables[ key ] = arguments.data[ key ];
            }
        }
        return this;
    }
    /**
     * Returns this object's public data as a serializable memento.
     * @returns struct
     */
    public struct function getMemento() {
        var result = {};
        for (
            var key in listToArray( "id,deliveryId,requestKey,intentHash,actorId,actorLabel,priorState,priorAttemptCount,priorTransportCount,priorReason,priorProviderReference,additionalAttempts,createdDate" )
        ) {
            if ( !isNull( variables[ key ] ) ) {
                result[ key ] = variables[ key ];
            }
        }
        return result;
    }

}
