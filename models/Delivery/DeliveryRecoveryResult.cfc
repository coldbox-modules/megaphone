component accessors="true" {

    property name="status" setter="false";
    property name="replayed" setter="false";
    property name="receipt" setter="false";
    property name="delivery" setter="false";

    /**
     * Loads a recovery result and wraps its receipt as a public object.
     * @returns DeliveryRecoveryResult
     */
    public DeliveryRecoveryResult function init( struct data = {} ) {
        return configure( argumentCollection = arguments );
    }

    /**
     * Configures the DeliveryRecoveryResult after WireBox constructs and injects it.
     * @returns DeliveryRecoveryResult
     */
    public DeliveryRecoveryResult function configure( required struct data ) {
        for ( var key in arguments.data ) {
            if ( structKeyExists( arguments.data, key ) && !isNull( arguments.data[ key ] ) ) {
                variables[ key ] = key == "receipt" ? newNotificationRecoveryReceipt().configure(
                    arguments.data[ key ]
                ) : arguments.data[ key ];
            }
        }
        return this;
    }
    /**
     * Returns this object's public data as a serializable memento.
     * @returns struct
     */
    public struct function getMemento() {
        var result = { "status": variables.status };
        if ( !isNull( variables.replayed ) ) {
            result.replayed = variables.replayed;
        }
        if ( !isNull( variables.receipt ) ) {
            result.receipt = variables.receipt.getMemento();
        }
        if ( !isNull( variables.delivery ) ) {
            result.delivery = variables.delivery.getMemento();
        }
        return result;
    }

    /**
     * Supplies a fresh NotificationRecoveryReceipt using the application's WireBox mapping.
     * @returns NotificationRecoveryReceipt
     */
    private NotificationRecoveryReceipt function newNotificationRecoveryReceipt()
        provider="NotificationRecoveryReceipt@megaphone"
    {
    }

}
