component accessors="true" {

    property name="id" setter="false";
    property name="eventId" setter="false";
    property name="notifiableType" setter="false";
    property name="notifiableId" setter="false";
    property name="channelName" setter="false";
    property name="deviceId" setter="false";
    property name="routingData" setter="false";
    property name="routingHash" setter="false";
    property name="state" setter="false";
    property name="attemptCount" setter="false";
    property name="transportCount" setter="false";
    property name="recoveryAllowance" setter="false";
    property name="availableDate" setter="false";
    property name="createdDate" setter="false";
    property name="updatedDate" setter="false";
    property name="settledDate" setter="false";
    property name="leaseToken" setter="false";
    property name="leaseUntil" setter="false";
    property name="transportStartedDate" setter="false";
    property name="reason" setter="false";
    property name="providerReference" setter="false";
    property name="created" setter="false";
    property name="attributes" setter="false";

    public NotificationDelivery function init( struct data = {} ) {
        variables.attributes = duplicate( arguments.data.attributes ?: {} );
        for ( var key in arguments.data ) {
            if (
                listFindNoCase(
                    "id,eventId,notifiableType,notifiableId,channelName,deviceId,routingData,routingHash,state,attemptCount,transportCount,recoveryAllowance,availableDate,createdDate,updatedDate,settledDate,leaseToken,leaseUntil,transportStartedDate,reason,providerReference,created",
                    key
                )
            ) {
                variables[ key ] = arguments.data[ key ];
            } else if (
                !listFindNoCase( "recipientType,recipientId,channel,attributes", key ) && !isNull(
                    arguments.data[ key ]
                )
            ) {
                variables.attributes[ key ] = arguments.data[ key ];
            }
        }
        return this;
    }

    public struct function getMemento() {
        var result = { "attributes": duplicate( variables.attributes ) };
        for (
            var key in listToArray( "id,eventId,notifiableType,notifiableId,channelName,deviceId,routingData,routingHash,state,attemptCount,transportCount,recoveryAllowance,availableDate,createdDate,updatedDate,settledDate,leaseToken,leaseUntil,transportStartedDate,reason,providerReference,created" )
        ) {
            if ( !isNull( variables[ key ] ) ) {
                result[ key ] = variables[ key ];
            }
        }
        return result;
    }

}
