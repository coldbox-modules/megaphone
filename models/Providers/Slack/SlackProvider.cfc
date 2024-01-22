component extends="megaphone.models.Providers.BaseProvider" accessors="true" {

    property name="wirebox" inject="wirebox";
    property name="client";

    function onDIComplete() {
        try {
            variables.client = variables.wirebox.getInstance( "HyperBuilder@hyper" );
        } catch ( Injector.InstanceNotFoundException e ) {
            throw(
                type = "Megaphone.Provider.MissingDependency",
                message = "You must install the hyper module to use the SlackProvider"
            );
        }

        if ( !variables.properties.keyExists( "token" ) || !variables.properties.token.len() ) {
            throw(
                type = "Megaphone.Provider.MissingProperty",
                message = "You must provide a `token` to use the SlackProvider."
            );
        }

        param variables.properties.defaultChannel = "general";

        variables.client.defaults.setBaseUrl( "https://slack.com/api/" ).asJson();
    }

    public string function getProviderName() {
        return "SlackProvider";
    }

    public BaseNotification function notify( required any notifiable, required BaseNotification notification ) {
        var route = determineRoute( arguments.notifiable, arguments.notification );

        var slackMessage = arguments.notification.routeForType(
            type = "slack",
            notifiable = notifiable,
            channelName = getName(),
            additionalArgs = {
                "newSlackMessage": () => {
                    return variables.wirebox.getInstance( "SlackMessage@megaphone" );
                }
            }
        );

        if ( isObject( slackMessage ) ) {
            slackMessage = slackMessage.getMemento();
        }

        if ( !slackMessage.keyExists( "channel" ) ) {
            slackMessage[ "channel" ] = route.getChannel();
        } else {
            route.setChannel( slackMessage.channel );
        }

        var res = variables.client
            .new()
            .withHeaders( { "Authorization": "Bearer #route.getToken()#" } )
            .post( "chat.postMessage", slackMessage );

        if ( !res.isSuccess() || res.json().ok != true ) {
            if ( isJSON( res.getData() ) ) {
                throw(
                    type = "Megaphone.Provider.ProviderError",
                    message = "Slack API call failed with error [#res.json().error#].",
                    detail = res.getData(),
                    extendedinfo = serializeJSON( res.getMemento() )
                );
            } else {
                throw(
                    type = "Megaphone.Provider.ProviderError",
                    message = "Slack API call failed.",
                    detail = res.getData(),
                    extendedinfo = serializeJSON( res.getMemento() )
                );
            }
        }

        return arguments.notification;
    }

    private SlackRoute function determineRoute( required any notifiable, required BaseNotification notification ) {
        var route = routeNotificationFor(
            type = "slack",
            notifiable = notifiable,
            channelName = getName(),
            additionalArgs = {
                "newSlackRoute": ( channel, token ) => {
                    return variables.wirebox.getInstance(
                        "SlackRoute@megaphone",
                        { "channel": channel, "token": token }
                    );
                }
            },
            optional = true
        );

        if ( isSimpleValue( route ) ) {
            return newSlackRoute().setChannel( route ).setToken( variables.properties.token );
        }

        if ( isNull( route.getChannel() ) ) {
            route.setChannel( variables.properties.defaultChannel );
        }

        if ( isNull( route.getToken() ) ) {
            route.setToken( variables.properties.token );
        }

        return route;
    }

    private SlackRoute function newSlackRoute() provider="SlackRoute@megaphone" {
    }

}
