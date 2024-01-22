component accessors="true" {

    property name="notifiableId" default="1";
    property name="notifiableType" default="explorer";

    property name="slackToken";
    property name="slackChannel";

    function routeNotificationForSlack( newSlackRoute ) {
        return newSlackRoute( getSlackChannel(), getSlackToken() );
    }

}
