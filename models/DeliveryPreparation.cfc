component accessors="true" {

    property name="status" setter="false";
    property name="reason" setter="false";
    property name="retryDate" setter="false";
    property name="data" setter="false";

    public DeliveryPreparation function init( struct data = {} ) {
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

    public any function getRetryDate() {
        return variables.retryDate ?: javacast( "null", "" );
    }

    public struct function getMemento() {
        var result = {};
        for ( var key in listToArray( "status,reason,retryDate" ) ) {
            if ( !isNull( variables[ key ] ) ) {
                result[ key ] = variables[ key ];
            }
        }
        return result;
    }

}
