component accessors="true" {

    property name="status" setter="false";
    property name="replayed" setter="false";
    property name="receipt" setter="false";
    property name="delivery" setter="false";

    public DeliveryRecoveryResult function init( required struct data ) {
        for ( var key in arguments.data ) {
            if ( !isNull( arguments.data[ key ] ) ) {
                variables[ key ] = key == "receipt" ? new megaphone.models.NotificationRecoveryReceipt(
                    arguments.data[ key ]
                ) : arguments.data[ key ];
            }
        }
        return this;
    }
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

}
