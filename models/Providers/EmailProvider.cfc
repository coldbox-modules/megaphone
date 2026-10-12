component extends="BaseProvider" accessors="true" {

    property name="moduleService" inject="box:moduleService";
    property name="log" inject="logbox:logger:{this}";
    property name="wirebox" inject="wirebox";
    property name="mailService";

    public DeliveryPreparation function prepareDelivery(
        required any notifiable,
        required any notification,
        required any delivery
    ) {
        return durableAdapter().prepareDelivery( arguments.notifiable, arguments.notification, arguments.delivery );
    }

    public DeliveryResult function sendDelivery( required any prepared, required any delivery ) {
        return durableAdapter().sendDelivery( arguments.prepared, arguments.delivery );
    }

    public boolean function supportsDurableDelivery() {
        var properties = getProperties();
        return structKeyExists( properties, "durableAdapter" ) && len( properties.durableAdapter );
    }

    private any function durableAdapter() {
        if ( !supportsDurableDelivery() ) {
            throw(
                type = "Megaphone.Configuration.UnsupportedDurableProvider",
                message = "Durable email requires an explicit receipt-aware adapter."
            );
        }
        return variables.wirebox.getInstance( getProperties().durableAdapter );
    }

    function onDIComplete() {
        try {
            variables.moduleService.activateModule( "cbmailservices" );
            variables.mailService = variables.wirebox.getInstance( "MailService@cbmailservices" );
        } catch ( IllegalModuleState e ) {
            throw(
                type = "Megaphone.Provider.MissingDependency",
                message = "You must install the cbmailservices module to use the EmailProvider",
                extendedInfo = serializeJSON( e )
            );
        } catch ( Injector.InstanceNotFoundException e ) {
            throw(
                type = "Megaphone.Provider.MissingDependency",
                message = "You must install the cbmailservices module to use the EmailProvider",
                extendedInfo = serializeJSON( e )
            );
        }

        param variables.properties.mailer = variables.mailService.getDefaultProtocol();
        if ( !variables.properties.keyExists( "onSuccess" ) ) {
            variables.properties.onSuccess = ( results, mail ) => {
                if ( variables.log.canInfo() ) {
                    variables.log.info(
                        "Email successfully sent",
                        { "messages": results.messages, "mail": mail.getMemento() }
                    );
                }
            };
        }
        if ( !variables.properties.keyExists( "onError" ) ) {
            variables.properties.onError = ( results, mail ) => {
                if ( variables.log.canError() ) {
                    variables.log.error(
                        "Error sending email: #arguments.results.messages.toList( "; " )#",
                        { "messages": results.messages, "mail": mail.getMemento() }
                    );
                }
            };
        }
    }

    public string function getProviderName() {
        return "EmailProvider";
    }

    public BaseNotification function notify( required any notifiable, required BaseNotification notification ) {
        var mail = arguments.notification.routeForType(
            type = "email",
            notifiable = notifiable,
            channelName = getName(),
            additionalArgs = {
                "newMail": () => {
                    param arguments.mailer = variables.properties.mailer;
                    return variables.mailService.newMail( argumentCollection = arguments );
                }
            }
        );

        if ( mail.getProperty( "to" ) == "" ) {
            mail.setProperty( "to", routeNotificationFor( "email", notifiable, getName() ) );
        }

        variables.mailService
            .send( mail )
            .onSuccess( variables.properties.onSuccess )
            .onError( variables.properties.onError );

        return arguments.notification;
    }

}
