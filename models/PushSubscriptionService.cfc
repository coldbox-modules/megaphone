/** Browser subscriptions are validated and sealed before entering storage. */
component singleton {

    property name="store" inject="SubscriptionStore@megaphone";
    property name="notificationService" inject="NotificationService@megaphone";

    public struct function register(
        required any notifiable,
        required struct subscription,
        required string label,
        string existingId = "",
        any expiresDate,
        string channelName = "push"
    ) {
        var channel = variables.notificationService.getChannel( arguments.channelName );
        var sealed = channel.sealSubscription( arguments.notifiable, arguments.subscription );
        return variables.store.register(
            notifiable = arguments.notifiable,
            endpointHash = lCase( hash( arguments.subscription.endpoint, "SHA-256" ) ),
            sealedData = sealed,
            label = arguments.label,
            existingId = arguments.existingId,
            expiresDate = arguments.expiresDate ?: javacast( "null", "" )
        );
    }

    public array function getRegistrations( required any notifiable, boolean activeOnly = true, date clock = now() ) {
        return variables.store.registrations( argumentCollection = arguments );
    }
    public any function getActiveRegistration( required any notifiable, required string id, date clock = now() ) {
        var row = variables.store.activeRegistration( argumentCollection = arguments );
        if ( isNull( row ) ) {
            return;
        }
        row.notifiableType = row.recipientType;
        row.notifiableId = row.recipientId;
        structDelete( row, "recipientType" );
        structDelete( row, "recipientId" );
        return row;
    }
    public boolean function rename( required any notifiable, required string id, required string label ) {
        return variables.store.rename( argumentCollection = arguments );
    }
    public boolean function disconnect( required any notifiable, required string id ) {
        return variables.store.disconnect( argumentCollection = arguments );
    }
    public void function setExcluded(
        required any notifiable,
        required string notificationType,
        required string deviceId,
        required boolean excluded
    ) {
        variables.store.setExcluded( argumentCollection = arguments );
    }
    public array function getExcludedIds( required any notifiable, required string notificationType ) {
        return variables.store.excludedIds( argumentCollection = arguments );
    }
    public numeric function retireExpired( any notifiable, date clock = now(), numeric limit = 100 ) {
        return variables.store.retireExpired( argumentCollection = arguments );
    }

    public numeric function pruneInactive( required date beforeDate, numeric limit = 100 ) {
        return variables.store.pruneInactive( argumentCollection = arguments );
    }
    public void function deleteNotifiable( required any notifiable ) {
        variables.store.deleteRecipient( arguments.notifiable );
    }

    public array function selectDevices( required array devices, array excludedIds = [] ) {
        var selected = [];
        var seen = {};
        for ( var device in arguments.devices ) {
            if ( !isStruct( device ) || !len( device.id ?: "" ) ) {
                throw( type = "Megaphone.Push.InvalidDevice", message = "A device needs a stable registration ID." );
            }
            if ( structKeyExists( device, "active" ) && !device.active ) {
                continue;
            }
            if ( !arguments.excludedIds.findNoCase( device.id ) && !seen.keyExists( device.id ) ) {
                seen[ device.id ] = true;
                selected.append( duplicate( device ) );
            }
        }
        return selected;
    }

}
