/** Registered Web Push channel. Java SDK/configuration is resolved only when push is used. */
component extends="BaseProvider" accessors="true" implements="megaphone.models.Interfaces.IDurableNotificationProvider" {

    property name="subscriptions" inject="PushSubscriptionService@megaphone";
    property name="wirebox" inject="wirebox";

    /**
     * Returns the Provider type used to validate channel configuration.
     * @returns string
     */
    public string function getProviderName() {
        return "WebPushProvider";
    }

    /**
     * Selects owned active destinations and applies notification-specific device exclusions.
     * @returns array
     */
    public array function getDeliveryTargets( required any notifiable, required any notification ) {
        var route = routeNotificationFor(
            "WebPush",
            arguments.notifiable,
            getName(),
            {},
            true
        );
        var owned = variables.subscriptions.getRegistrations( arguments.notifiable );
        var devices = isNull( route ) ? owned : route.filter( ( device ) => owned.some( ( candidate ) => candidate.id == device.id ) );
        var context = arguments.notification.getDeliveryContext( arguments.notifiable, getName() );
        if ( len( context.deviceId ?: "" ) ) {
            devices = devices.filter( ( device ) => device.id == context.deviceId );
        }
        return variables.subscriptions
            .selectDevices(
                devices,
                variables.subscriptions.getExcludedIds(
                    arguments.notifiable,
                    arguments.notification.getNotificationType()
                )
            )
            .map( ( device ) => device.id );
    }

    /**
     * Validates and encrypts a browser subscription using the recipient's runtime context.
     * @returns string
     */
    public string function sealSubscription( required any notifiable, required struct subscription ) {
        var runtime = getRuntime();
        if ( !runtime.enabled() ) {
            throw( type = "Megaphone.Push.ConfigurationUnavailable", message = "Push registration is unavailable." );
        }
        try {
            runtime.transport().prepare( arguments.subscription, { "title": "" }, 0 );
        } catch ( Megaphone.Push.InvalidRequest invalid ) {
            rethrow;
        } catch ( any unavailable ) {
            throw(
                type = "Megaphone.Push.ConfigurationUnavailable",
                message = "Push registration configuration is unavailable."
            );
        }
        try {
            return runtime.cipher().seal( arguments.subscription, runtime.context( arguments.notifiable ) );
        } catch ( any unavailable ) {
            throw(
                type = "Megaphone.Push.ConfigurationUnavailable",
                message = "Push subscription storage is unavailable."
            );
        }
    }

    /**
     * Sends a populated Notification synchronously through its enabled channels.
     * @returns BaseNotification
     */
    public BaseNotification function notify( required any notifiable, required BaseNotification notification ) {
        for ( var deviceId in getDeliveryTargets( arguments.notifiable, arguments.notification ) ) {
            var delivery = newNotificationDelivery().configure( {
                "id": arguments.notification.getId(),
                "notifiableId": arguments.notifiable.getNotifiableId(),
                "notifiableType": arguments.notifiable.getNotifiableType(),
                "channelName": getName(),
                "deviceId": deviceId
            } );
            var ready = prepareDelivery( arguments.notifiable, arguments.notification, delivery );
            if ( ready.getStatus() == "ready" ) {
                sendDelivery( ready, delivery );
            }
        }
        return arguments.notification;
    }

    /**
     * Prepares one durable delivery without sending it.
     * @returns DeliveryPreparation
     */
    public DeliveryPreparation function prepareDelivery(
        required any notifiable,
        required any notification,
        required any delivery
    ) {
        var runtime = getRuntime();
        if ( !runtime.enabled() ) {
            return preparation( "deferred", "push-disabled" );
        }
        variables.subscriptions.retireExpired( arguments.notifiable );
        var device = variables.subscriptions.getActiveRegistration(
            arguments.notifiable,
            arguments.delivery.getDeviceId()
        );
        if (
            isNull( device ) || variables.subscriptions
                .getExcludedIds( arguments.notifiable, arguments.notification.getNotificationType() )
                .findNoCase( arguments.delivery.getDeviceId() )
        ) {
            return preparation( "suppressed", "push-device-unavailable-or-excluded" );
        }
        var transport = "";
        var cipher = "";
        try {
            transport = runtime.transport();
            cipher = runtime.cipher();
        } catch ( any ignored ) {
            return preparation( "deferred", "push-configuration-unavailable" );
        }
        var subscription = "";
        try {
            subscription = cipher.unseal( device.sealedData, runtime.context( arguments.notifiable ) );
        } catch ( any ignored ) {
            return preparation( "permanent", "push-registration-unreadable" );
        }
        var payload = arguments.notification.routeForType(
            "WebPush",
            arguments.notifiable,
            getName(),
            { "delivery": arguments.delivery }
        );
        var preparedRequest = "";
        var context = arguments.notification.getDeliveryContext( arguments.notifiable, getName() );
        try {
            preparedRequest = transport.prepare(
                subscription,
                payload,
                structKeyExists( context, "ttlSeconds" ) ? context.ttlSeconds : 3600
            );
        } catch ( any ignored ) {
            return preparation( "permanent", "push-request-invalid" );
        }
        return newDeliveryPreparation().configure( {
            "status": "ready",
            "data": {
                "notifiable": arguments.notifiable,
                "notificationType": arguments.notification.getNotificationType(),
                "sealedData": device.sealedData,
                "transport": transport,
                "request": preparedRequest
            }
        } );
    }

    /**
     * Sends one prepared delivery and returns an explicit transport outcome.
     * @returns DeliveryResult
     */
    public DeliveryResult function sendDelivery( required any prepared, required any delivery ) {
        var data = arguments.prepared.getData();
        var current = variables.subscriptions.getActiveRegistration( data.notifiable, arguments.delivery.getDeviceId() );
        if (
            !getRuntime().enabled() || isNull( current ) || current.sealedData != data.sealedData || variables.subscriptions
                .getExcludedIds( data.notifiable, data.notificationType )
                .findNoCase( arguments.delivery.getDeviceId() )
        ) {
            return newDeliveryResult().configure( { "status": "permanent", "reason": "push-source-changed-before-send" } );
        }
        var policy = variables.wirebox.getInstance( "NotificationRuntime@megaphone" ).resolve( "eligibilityPolicy" );
        if ( !isNull( policy ) && arguments.delivery.getMemento().keyExists( "eventId" ) ) {
            var event = variables.wirebox
                .getInstance( "NotificationDeliveryService@megaphone" )
                .getEvent( arguments.delivery.getEventId() );
            if ( isNull( event ) || policy.check( arguments.delivery, data.notifiable, event ).getStatus() != "ready" ) {
                return newDeliveryResult().configure( { "status": "permanent", "reason": "push-source-changed-before-send" } );
            }
        }
        var outcome = data.transport.sendPrepared( data.request );
        if ( outcome.retireSubscription ?: false ) {
            variables.subscriptions.disconnect( data.notifiable, arguments.delivery.getDeviceId() );
        }
        outcome.status = outcome.outcome;
        structDelete( outcome, "outcome" );
        return newDeliveryResult().configure( outcome );
    }

    /**
     * Resolves the application override or the default Web Push runtime lazily.
     * @returns any
     */
    private any function getRuntime() {
        var properties = getProperties();
        var configured = structKeyExists( properties, "runtime" ) ? properties.runtime : "";
        if ( !isSimpleValue( configured ) ) {
            return configured;
        }
        if ( len( configured ) ) {
            return variables.wirebox.getInstance( configured );
        }
        return variables.wirebox.getInstance( "WebPushRuntime@megaphone", { "properties": getProperties() } );
    }

    /**
     * Creates a typed Provider preparation decision from a status and reason.
     * @returns DeliveryPreparation
     */
    private DeliveryPreparation function preparation( required string status, required string reason ) {
        return newDeliveryPreparation().configure( { "status": arguments.status, "reason": arguments.reason } );
    }

    /**
     * Supplies a fresh DeliveryPreparation using the application's WireBox mapping.
     * @returns DeliveryPreparation
     */
    private DeliveryPreparation function newDeliveryPreparation() provider="DeliveryPreparation@megaphone" {
    }

    /**
     * Supplies a fresh DeliveryResult using the application's WireBox mapping.
     * @returns DeliveryResult
     */
    private DeliveryResult function newDeliveryResult() provider="DeliveryResult@megaphone" {
    }

    /**
     * Supplies a fresh NotificationDelivery using the application's WireBox mapping.
     * @returns NotificationDelivery
     */
    private NotificationDelivery function newNotificationDelivery() provider="NotificationDelivery@megaphone" {
    }

}
