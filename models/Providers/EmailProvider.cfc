component extends="BaseProvider" accessors="true" {

    property name="wirebox" inject="wirebox";
    property name="mailService";

    function onDIComplete() {
        try {
            variables.mailService = variables.wirebox.getInstance( "MailService@cbmailservices" );
        } catch ( Injector.InstanceNotFoundException e ) {
            throw(
                type = "Megaphone.Provider.MissingDependency",
                message = "You must install the cbmailservices module to use the EmailProvider"
            );
        }
    }

    public EmailProvider function setProperties( struct properties = {} ) {
        variables.properties = arguments.properties;
        param variables.properties.mailer = "default";
        if ( !variables.properties.keyExists( "onSuccess" ) ) {
            variables.properties.onSuccess = () => {
            };
        }
        if ( !variables.properties.keyExists( "onError" ) ) {
            variables.properties.onError = () => {
            };
        }
        return this;
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
