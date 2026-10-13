component accessors="true" {

    property name="status" setter="false";
    property name="reason" setter="false";
    property name="providerReference" setter="false";
    property name="retryDate" setter="false";
    property name="retireSubscription" setter="false";

    /**
     * Copies supplied transport fields, defaulting to ambiguous acceptance.
     * @returns DeliveryResult
     */
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

    /**
     * Returns the scheduled retry date, or null when none was supplied.
     * @returns any
     */
    public any function getRetryDate() {
        return variables.retryDate ?: javacast( "null", "" );
    }

    /**
     * Returns this object's public data as a serializable memento.
     * @returns struct
     */
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
