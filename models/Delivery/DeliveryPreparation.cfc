component accessors="true" {

    property name="status" setter="false";
    property name="reason" setter="false";
    property name="retryDate" setter="false";
    property name="data" setter="false";

    /**
     * Copies supplied preparation fields, defaulting to a ready decision.
     * @returns DeliveryPreparation
     */
    public DeliveryPreparation function init( struct data = {} ) {
        return configure( argumentCollection = arguments );
    }

    /**
     * Configures the DeliveryPreparation after WireBox constructs and injects it.
     * @returns DeliveryPreparation
     */
    public DeliveryPreparation function configure( struct data = {} ) {
        variables.status = "ready";
        variables.reason = "";
        variables.data = {};
        for ( var key in arguments.data ) {
            if ( !isNull( arguments.data[ key ] ) && listFindNoCase( "status,reason,retryDate,data", key ) ) {
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
     * Returns the preparation decision without exposing prepared transport data.
     * @returns struct
     */
    public struct function getMemento() {
        var result = {};
        for ( var key in listToArray( "status,reason,retryDate" ) ) {
            if ( structKeyExists( variables, key ) && !isNull( variables[ key ] ) ) {
                result[ key ] = variables[ key ];
            }
        }
        return result;
    }

}
