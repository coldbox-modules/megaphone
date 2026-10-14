/** Internal mail provider: delegates to the named definition's receipt-aware email channel. */
component extends="BaseProvider" {

    property name="digests" inject="EmailDigestService@megaphone";
    property name="notifications" inject="NotificationService@megaphone";

    /**
     * Returns the Provider type used to validate channel configuration.
     * @returns string
     */
    public string function getProviderName() {
        return "EmailDigestBatchProvider";
    }
    /**
     * Renders eligible batch items and prepares mail through the named email channel.
     * @returns DeliveryPreparation
     */
    public DeliveryPreparation function prepareDelivery(
        required any notifiable,
        required any notification,
        required any delivery
    ) {
        var ready = variables.digests.prepareBatch(
            arguments.notifiable,
            arguments.notification.getQueueProperties().batchId
        );
        if ( ready.status != "ready" ) {
            return newDeliveryPreparation().configure( { "status": ready.status, "reason": ready.reason } );
        }
        if ( ready.definition.emailChannel == "emailDigestBatch" ) {
            throw(
                type = "Megaphone.Digests.InvalidDefinition",
                message = "A batch email channel cannot route to itself."
            );
        }
        var channel = variables.notifications.getChannel( ready.definition.emailChannel );
        if (
            !isCustomFunction( channel.prepareDelivery ?: "" ) || !isCustomFunction( channel.sendDelivery ?: "" ) ||
            ( isCustomFunction( channel.supportsDurableDelivery ?: "" ) && !channel.supportsDurableDelivery() )
        ) {
            throw(
                type = "Megaphone.Digests.MissingMailAdapter",
                message = "Digests require a receipt-aware durable email channel."
            );
        }
        var rendered = variables.digests
            .resolveCollaborator( ready.definition.renderer )
            .render(
                arguments.notifiable,
                ready.definition,
                ready.batch,
                ready.items
            );
        if ( !isInstanceOf( rendered, "megaphone.models.BaseNotification" ) ) {
            throw(
                type = "Megaphone.Digests.InvalidRender",
                message = "Digest renderers return a BaseNotification with toEmail()."
            );
        }
        rendered.setId( ready.batch.id );
        var mail = channel.prepareDelivery( arguments.notifiable, rendered, arguments.delivery );
        if ( mail.getStatus() != "ready" ) {
            return mail;
        }
        return newDeliveryPreparation().configure( {
            "data": {
                "batchId": ready.batch.id,
                "notifiable": notifiable,
                "itemIds": ready.items.map( ( item ) => item.id ),
                "channel": channel,
                "mail": mail
            }
        } );
    }
    /**
     * Rechecks the rendered batch and records transport start before external I/O.
     * @returns DeliveryPreparation
     * @internal
     */
    public DeliveryPreparation function startDeliveryTransport(
        required any prepared,
        required any delivery,
        required string token
    ) {
        return variables.digests.startBatchTransport( arguments.prepared, arguments.delivery, arguments.token );
    }
    /**
     * Sends the prepared mail and returns the email channel transport outcome.
     * @returns DeliveryResult
     */
    public DeliveryResult function sendDelivery( required any prepared, required any delivery ) {
        var data = arguments.prepared.getData();
        return data.channel.sendDelivery( data.mail, arguments.delivery );
    }
    /**
     * Supplies a fresh DeliveryPreparation through WireBox.
     * @returns DeliveryPreparation
     */
    private DeliveryPreparation function newDeliveryPreparation() provider="DeliveryPreparation@megaphone" {
    }

}
