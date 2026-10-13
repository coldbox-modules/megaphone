component accessors="true" {

    property name="id" setter="false";
    property name="namespace" setter="false";
    property name="eventKey" setter="false";
    property name="version" setter="false";
    property name="type" setter="false";
    property name="payload" setter="false";
    property name="payloadHash" setter="false";
    property name="createdDate" setter="false";
    property name="notificationMapping" setter="false";
    property name="created" setter="false";
    property name="expired" setter="false";

    /**
     * Copies persisted event fields into the public event object.
     * @returns NotificationEvent
     */
    public NotificationEvent function init( struct data = {} ) {
        variables.id = "";
        variables.created = false;
        variables.expired = false;
        variables.notificationMapping = "";
        for ( var key in arguments.data ) {
            if (
                listFindNoCase(
                    "id,namespace,eventKey,version,type,payload,payloadHash,createdDate,notificationMapping,created,expired",
                    key
                )
            ) {
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
            var key in listToArray( "id,namespace,eventKey,version,type,payload,payloadHash,createdDate,notificationMapping,created,expired" )
        ) {
            if ( !isNull( variables[ key ] ) ) {
                result[ key ] = variables[ key ];
            }
        }
        return result;
    }

}
