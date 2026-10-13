component accessors="true" {

    property name="id" setter="false";
    property name="deliveryId" setter="false";
    property name="number" setter="false";
    property name="leaseToken" setter="false";
    property name="outcome" setter="false";
    property name="providerReference" setter="false";
    property name="reason" setter="false";
    property name="startedDate" setter="false";
    property name="transportStartedDate" setter="false";
    property name="finishedDate" setter="false";
    /**
     * Copies attempt history into the public attempt object.
     * @returns NotificationDeliveryAttempt
     */
    public NotificationDeliveryAttempt function init( required struct data ) {
        for (
            var key in listToArray( "id,deliveryId,number,leaseToken,outcome,providerReference,reason,startedDate,transportStartedDate,finishedDate" )
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
            var key in listToArray( "id,deliveryId,number,leaseToken,outcome,providerReference,reason,startedDate,transportStartedDate,finishedDate" )
        ) {
            if ( !isNull( variables[ key ] ) ) {
                result[ key ] = variables[ key ];
            }
        }
        return result;
    }

}
