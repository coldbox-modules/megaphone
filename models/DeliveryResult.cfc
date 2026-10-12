component accessors="true" {

    property name="status" setter="false";
    property name="reason" setter="false";
    property name="providerReference" setter="false";
    property name="retryDate" setter="false";
    property name="retireSubscription" setter="false";

    public DeliveryResult function init( struct data = {} ) {
        variables.status = "ambiguous";
        variables.reason = "";
        variables.providerReference = "";
        variables.retireSubscription = false;
        for ( var key in arguments.data ) {
            if (
                !isNull( arguments.data[ key ] ) && listFindNoCase(
                    "status,reason,providerReference,retryDate,retireSubscription",
                    key
                )
            ) {
                variables[ key ] = arguments.data[ key ];
            }
        }
        return this;
    }

    public any function getRetryDate() {
        return variables.retryDate ?: javacast( "null", "" );
    }

    public struct function getMemento() {
        var result = {};
        for ( var key in listToArray( "status,reason,providerReference,retryDate,retireSubscription" ) ) {
            if ( !isNull( variables[ key ] ) ) {
                result[ key ] = variables[ key ];
            }
        }
        return result;
    }

}
