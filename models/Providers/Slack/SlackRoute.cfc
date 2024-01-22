component accessors="true" {

    property name="channel";
    property name="token";

    public SlackRoute function init( string channel, string token ) {
        if ( !isNull( arguments.channel ) ) {
            variables.channel = arguments.channel;
        }

        if ( !isNull( arguments.token ) ) {
            variables.token = arguments.token;
        }

        return this;
    }

}
